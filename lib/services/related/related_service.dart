import 'package:tucao/http/video_http.dart';
import 'package:tucao/models/video.dart';
import 'package:tucao/services/related/related_ranker.dart';
import 'package:tucao/services/related/series_parser.dart';
import 'package:tucao/utils/logger.dart';

/// 播放页简介下方的相关视频.
///
/// 站点没有推荐接口, 这里用作品名多路搜索召回候选, 再交给
/// [RelatedRanker] 去重排序. 召回结果按 hid 缓存在内存里, 重启即失效.
abstract final class RelatedService {
  /// 内存缓存的视频个数上限.
  static const cacheLimit = 32;

  /// 单次加载最多发出的搜索请求数.
  static const queryLimit = 6;

  /// 每路搜索取的条数, 站点超过 20 会返回空列表.
  static const pageSize = 20;

  /// 主名按分区分开搜: 完结番组多是整季合集, 剧场版分区收剧场版与 OVA,
  /// 新番父分区补上连载. 不限分区的一路兜住影剧等其他分区.
  static const _primaryTypeIds = <int?>[10, 26, 24, null];

  /// 最近使用的排在末尾, 超出上限时从头部淘汰.
  static final _cache = <String, Future<List<VideoModel>>>{};

  /// 取当前视频的相关视频, 已经排好序.
  ///
  /// 全部搜索都失败时抛出异常, 部分失败只记日志.
  static Future<List<RelatedEntry>> load(VideoModel current) async {
    final candidates = await _recall(current);
    final ranked = RelatedRanker.rank(current, candidates);
    final same = ranked.where((entry) => entry.sameSeries).length;
    Log.d('相关视频 ${current.hid}: 共 ${ranked.length} 条, 同系列 $same 条');
    return ranked;
  }

  static Future<List<VideoModel>> _recall(VideoModel current) {
    final cached = _cache.remove(current.hid);
    if (cached != null) {
      _cache[current.hid] = cached;
      return cached;
    }
    final future = _search(current);
    _cache[current.hid] = future;
    while (_cache.length > cacheLimit) {
      _cache.remove(_cache.keys.first);
    }
    // 失败的结果不缓存, 重试时重新请求.
    future.catchError((Object _) {
      if (identical(_cache[current.hid], future)) {
        _cache.remove(current.hid);
      }
      return const <VideoModel>[];
    });
    return future;
  }

  static Future<List<VideoModel>> _search(VideoModel current) async {
    final aliases = SeriesParser.parseAliases(current.title);
    if (aliases.isEmpty) {
      Log.i('相关视频 ${current.hid}: 标题里没有可用的作品名, 跳过搜索');
      return const [];
    }
    final queries = <(String, int?)>[
      for (final typeId in _primaryTypeIds) (aliases.first, typeId),
      for (final alias in aliases.skip(1)) (alias, null),
    ].take(queryLimit).toList();

    final watch = Stopwatch()..start();
    var failed = 0;
    Object? lastError;
    final results = await Future.wait([
      for (final (keyword, typeId) in queries)
        _query(keyword, typeId).catchError((Object error) {
          failed++;
          lastError = error;
          Log.w('相关视频搜索失败 "$keyword" tid=$typeId: $error');
          return const <VideoModel>[];
        }),
    ]);
    if (failed == queries.length) {
      throw lastError ?? StateError('相关视频搜索全部失败');
    }
    final candidates = [for (final list in results) ...list];
    Log.i(
      '相关视频 ${current.hid}: 作品名 $aliases, '
      '${queries.length} 路搜索 ($failed 路失败), '
      '召回 ${candidates.length} 条, 用时 ${watch.elapsedMilliseconds} ms',
    );
    return candidates;
  }

  static Future<List<VideoModel>> _query(String keyword, int? typeId) async {
    final response = await VideoHttp.search(
      keyword: keyword,
      page: 1,
      typeId: typeId,
      pageSize: pageSize,
      order: 'views',
    );
    if (!response.success) {
      throw StateError(response.message ?? '搜索失败');
    }
    return response.list;
  }
}
