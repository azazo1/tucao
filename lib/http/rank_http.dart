import 'package:dio/dio.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:tucao/common/constants.dart';
import 'package:tucao/models/video.dart';
import 'package:tucao/utils/http_util.dart';

/// 一个时间维度下的排行榜.
class RankGroup {
  const RankGroup({required this.title, this.period = 0, this.list = const []});

  /// 时间标题, 取页面上的原文, 如 今天.
  final String title;

  /// 时间维度对应的 period 值: 0 今天, 1 本周, 2 本月, 3 今年.
  ///
  /// 站点可能调整维度的顺序, 这里按标题匹配而不是按出现位置.
  final int period;

  /// 榜单内容, 顺序即排名.
  final List<VideoModel> list;
}

/// 热搜榜的一个关键词.
class HotKeyword {
  const HotKeyword({
    required this.rank,
    required this.keyword,
    required this.count,
  });

  final int rank;
  final String keyword;

  /// 搜索次数.
  final int count;
}

/// 站点榜单类型.
///
/// 除排行榜外, 站点还有几个同结构的榜单页, 它们只有分组维度不同.
enum RankType {
  hot('排行榜', 'html/hot.html', supportsChannel: true),
  danmaku('弹幕榜', 'html/danmu.html'),
  digg('神评论', 'html/digg.html'),
  zero('无人区', 'html/zero.html'),
  fav('追番榜', 'html/fav_hot.html'),
  user('u榜', 'html/user_hot.html');

  const RankType(this.label, this.path, {this.supportsChannel = false});

  final String label;
  final String path;

  /// 是否支持按分区筛选, 目前只有排行榜支持.
  final bool supportsChannel;

  String get url => '${Constants.baseUrl}$path';
}

/// 排行榜数据源.
///
/// 官方 json 接口的 rank.php 已经废弃, 现在只能抓排行榜页面.
abstract final class RankHttp {
  /// 时间维度标题与 period 值的对应关系.
  static const Map<String, int> periodTitles = {
    '今天': 0,
    '本周': 1,
    '本月': 2,
    '今年': 3,
  };

  /// 拉取排行榜.
  ///
  /// [typeId] 为空表示全站榜, [period] 为 0 今天, 1 本周, 2 本月, 3 今年.
  /// 页面返回全部时间维度, 因此 [period] 只影响站点返回的默认维度.
  static Future<List<RankGroup>> fetch({
    int? typeId,
    int period = 0,
    RankType type = RankType.hot,
    CancelToken? cancelToken,
  }) async {
    final query = <String>[
      if (type.supportsChannel && typeId != null) 'p=$typeId',
      if (period > 0) 't=$period',
    ];
    final url =
        '${type.url}${query.isEmpty ? '' : '?${query.join('&')}'}';
    final response = await HttpUtil.dio.get(
      url,
      cancelToken: cancelToken,
      options: Options(headers: {'user-agent': Constants.desktopUserAgent}),
    );
    return parseRankHtml(response.data.toString());
  }

  /// 拉取热搜榜.
  ///
  /// 该页面结构与其他榜单不同, 是关键词列表而不是视频列表.
  static Future<List<HotKeyword>> fetchHotSearch({
    CancelToken? cancelToken,
  }) async {
    final response = await HttpUtil.dio.get(
      '${Constants.baseUrl}html/hot_search.html',
      cancelToken: cancelToken,
      options: Options(headers: {'user-agent': Constants.desktopUserAgent}),
    );
    return parseHotSearchHtml(response.data.toString());
  }

  /// 解析热搜榜页面.
  ///
  /// 每条是一段形如 `45次1无修` 的文本, 依次是搜索次数, 排名与关键词.
  static List<HotKeyword> parseHotSearchHtml(String raw) {
    final document = html_parser.parse(raw);
    final list = <HotKeyword>[];
    for (final item in document.querySelectorAll('.time_item .item')) {
      final link = item.querySelector('a');
      if (link == null) {
        continue;
      }
      final match = RegExp(
        r'^(\d+)次(\d+)(.+)$',
      ).firstMatch(link.text.trim());
      if (match == null) {
        continue;
      }
      list.add(
        HotKeyword(
          count: int.tryParse(match.group(1)!) ?? 0,
          rank: int.tryParse(match.group(2)!) ?? 0,
          keyword: match.group(3)!.trim(),
        ),
      );
    }
    return list;
  }

  /// 解析排行榜页面.
  ///
  /// 页面结构为若干 `div.time_item`, 每个下面是 `div.time_title` 与
  /// `div.list`, list 里是 `div.item`: `a.p` 里的封面, `a.t` 的标题与地址,
  /// `.i` 里的播放数与作者. 结果按时间维度分组, 空榜单会被跳过.
  static List<RankGroup> parseRankHtml(String raw) {
    final document = html_parser.parse(raw);
    final groups = <RankGroup>[];
    for (final node in document.querySelectorAll('.time_item')) {
      final title = node.querySelector('.time_title')?.text.trim() ?? '';
      final list = <VideoModel>[];
      final seen = <String>{};
      for (final item in node.querySelectorAll('.list .item')) {
        final video = _parseItem(item, seen);
        if (video != null) {
          list.add(video);
        }
      }
      if (list.isEmpty) {
        continue;
      }
      groups.add(
        RankGroup(
          title: title,
          // 分组名不是时间文案时记为 -1, 由调用方决定怎么展示.
          period: periodTitles[title] ?? -1,
          list: list,
        ),
      );
    }
    return groups;
  }

  /// 解析单个榜单条目, 同一榜单内重复的视频只保留排名靠前的一次.
  static VideoModel? _parseItem(Element item, Set<String> seen) {
    final link = item.querySelector('a.t') ?? item.querySelector('a');
    if (link == null) {
      return null;
    }
    final hid = _parseHid(link.attributes['href'] ?? '');
    if (hid == null || !seen.add(hid)) {
      return null;
    }
    final info = item.querySelector('.i');
    return VideoModel(
      hid: hid,
      title: link.text.trim(),
      cover: _parseCover(item.querySelector('img')),
      playCount: _parseCount(info?.querySelector('span')?.text ?? ''),
      userName: info?.querySelector('a')?.text.trim() ?? '',
      userId: _parseUserId(info?.querySelector('a')?.attributes['href'] ?? ''),
    );
  }

  /// 封面地址写在 style 的 background-image 里, img 的 src 是占位图.
  static String _parseCover(Element? image) {
    final background = _parseBackground(image?.attributes['style'] ?? '');
    return background.isNotEmpty ? background : image?.attributes['src'] ?? '';
  }

  static String? _parseHid(String href) {
    final match = RegExp(r'/play/h?(\d+)/').firstMatch(href);
    return match?.group(1);
  }

  static int _parseUserId(String href) {
    final match = RegExp(r'/play/u(\d+)/').firstMatch(href);
    if (match == null) {
      return 0;
    }
    return int.tryParse(match.group(1)!) ?? 0;
  }

  static String _parseBackground(String style) {
    final match = RegExp(r'url\(([^)]+)\)').firstMatch(style);
    if (match == null) {
      return '';
    }
    return match.group(1)!.replaceAll(RegExp(r'''^["']|["']$'''), '').trim();
  }

  static int _parseCount(String text) {
    final match = RegExp(r'([\d,]+)').firstMatch(text);
    if (match == null) {
      return 0;
    }
    return int.tryParse(match.group(1)!.replaceAll(',', '')) ?? 0;
  }
}
