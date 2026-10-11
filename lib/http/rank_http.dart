import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:tucao/common/constants.dart';
import 'package:tucao/http/api_path.dart';
import 'package:tucao/models/video.dart';
import 'package:tucao/utils/http_util.dart';

/// 排行榜数据源.
///
/// 官方 json 接口的 rank.php 已经废弃, 现在只能抓排行榜页面.
abstract final class RankHttp {
  /// 拉取排行榜.
  ///
  /// [typeId] 为空表示全站榜, [period] 为 0 今天, 1 本周, 2 本月, 3 今年.
  static Future<List<VideoModel>> fetch({
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
    final response = await HttpUtil.dio.get(url, cancelToken: cancelToken);
    return parseRankHtml(response.data.toString(), typeId);
  }

  /// 解析排行榜页面.
  ///
  /// 页面结构为若干 `div.time_item`, 每个下面是 `div.list`, 其中每一项包含
  /// 视频地址, 封面和标题. 站点有时只返回第一个时间维度的榜单,
  /// 此时按页面实际存在的内容解析.
  static List<VideoModel> parseRankHtml(String raw, int? typeId) {
    final document = html_parser.parse(raw);
    final list = <VideoModel>[];
    final seen = <String>{};
    for (final item in document.querySelectorAll('.time_item .list .item')) {
      final link = item.querySelector('a.t') ?? item.querySelector('a');
      if (link == null) {
        continue;
      }
      final href = link.attributes['href'] ?? '';
      final hid = _parseHid(href);
      if (hid == null || !seen.add(hid)) {
        continue;
      }
      final image = item.querySelector('img');
      final cover = image?.attributes['style'] != null
          ? _parseBackground(image!.attributes['style']!)
          : image?.attributes['src'] ?? '';
      final countNode = item.querySelector('.i');
      list.add(
        VideoModel(
          hid: hid,
          title: link.text.trim(),
          typeId: typeId ?? 0,
          cover: cover,
          playCount: _parseCount(
            countNode?.querySelector('span')?.text ?? item.text,
          ),
        ),
      );
    }
    return list;
  }

  static String? _parseHid(String href) {
    final match = RegExp(r'/play/h?(\d+)/').firstMatch(href);
    return match?.group(1);
  }

  static String _parseBackground(String style) {
    final match = RegExp(r'url\(([^)]+)\)').firstMatch(style);
    return match?.group(1)?.replaceAll(RegExp(r'''^["']|["']$'''), '') ?? '';
  }

  static int _parseCount(String text) {
    final match = RegExp(r'([\d,]+)').firstMatch(text);
    if (match == null) {
      return 0;
    }
    return int.tryParse(match.group(1)!.replaceAll(',', '')) ?? 0;
  }
}
