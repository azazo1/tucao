import 'package:dio/dio.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:tucao/common/constants.dart';
import 'package:tucao/http/api_path.dart';
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
    CancelToken? cancelToken,
  }) async {
    final query = <String>[
      if (typeId != null) 'p=$typeId',
      if (period > 0) 't=$period',
    ];
    final url =
        '${Constants.baseUrl}${ApiPath.rankHtml}'
        '${query.isEmpty ? '' : '?${query.join('&')}'}';
    final response = await HttpUtil.dio.get(
      url,
      cancelToken: cancelToken,
      options: Options(headers: {'user-agent': Constants.desktopUserAgent}),
    );
    return parseRankHtml(response.data.toString());
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
        RankGroup(title: title, period: periodTitles[title] ?? 0, list: list),
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
