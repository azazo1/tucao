import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:tucao/common/constants.dart';
import 'package:tucao/models/video.dart';
import 'package:tucao/utils/http_util.dart';
import 'package:tucao/utils/logger.dart';

/// 本周新番的一个日期分组.
class WeekBgmGroup {
  WeekBgmGroup({
    required this.date,
    required this.weekday,
    required this.list,
  });

  /// 日期, 形如 2026-10-12.
  final String date;

  /// 星期, 形如 周一.
  final String weekday;

  /// 当天更新的番组, 解析时按日期归并, 因此是可变的.
  final List<VideoModel> list;

  /// 标题, 例如 `10-12 周一`.
  String get title {
    if (date.length >= 10) {
      return '${date.substring(5)} $weekday';
    }
    return '$date $weekday';
  }
}

/// 本周新番数据源.
///
/// 站点 `html/week_bgm.html` 按日期列出当天更新的番组, 没有 json 接口.
/// 页面结构是若干 `div.list`, 每个 list 顶部是 `div.title` 的日期与星期,
/// 下面是当天的 `div.item`.
abstract final class WeekBgmHttp {
  static Future<List<WeekBgmGroup>> fetch({CancelToken? cancelToken}) async {
    final response = await HttpUtil.dio.get(
      '${Constants.baseUrl}html/week_bgm.html',
      options: Options(headers: {'user-agent': Constants.desktopUserAgent}),
      cancelToken: cancelToken,
    );
    return parseWeekBgmHtml(response.data.toString());
  }

  /// 解析本周新番页面.
  ///
  /// 页面只有一个 `div.list`, 每个 `div.item` 带 `date` 属性,
  /// 因此按 date 属性分组, 而不是按页面上的标题块.
  static List<WeekBgmGroup> parseWeekBgmHtml(String raw) {
    final document = html_parser.parse(raw);
    // 保持页面顺序, 同时记录每个日期对应的分组下标.
    final indexOf = <String, int>{};
    final groups = <WeekBgmGroup>[];

    for (final item in document.querySelectorAll('.item')) {
      final link = item.querySelector('a.t') ?? item.querySelector('a.p');
      if (link == null) {
        continue;
      }
      final hid = _parseHid(link.attributes['href'] ?? '');
      if (hid == null) {
        continue;
      }
      final date = item.attributes['date'] ?? '';
      if (date.isEmpty) {
        continue;
      }

      final video = VideoModel(
        hid: hid,
        title: item.querySelector('a.t')?.text.trim() ?? link.text.trim(),
        cover: _parseCover(item),
        userName:
            item.querySelector('img')?.attributes['up'] ??
            item.querySelector('.i a')?.text.trim() ??
            '',
        playCount: _parseCount(
          item.querySelector('.i span')?.text ??
              item.querySelector('.c')?.text ??
              '',
        ),
      );

      final existing = indexOf[date];
      if (existing != null) {
        final group = groups[existing];
        // 同一天内重复投稿只保留一次.
        if (!group.list.any((e) => e.hid == hid)) {
          group.list.add(video);
        }
      } else {
        indexOf[date] = groups.length;
        groups.add(
          WeekBgmGroup(
            date: date,
            weekday: _weekdayOf(date),
            list: [video],
          ),
        );
      }
    }

    Log.i('本周新番解析完成, 共 ${groups.length} 个日期分组');
    return groups;
  }

  /// 由日期算出星期文案, 与站点显示一致.
  static String _weekdayOf(String date) {
    final parsed = DateTime.tryParse(date);
    if (parsed == null) {
      return '';
    }
    const names = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    return names[parsed.weekday - 1];
  }

  static String? _parseHid(String href) {
    final match = RegExp(r'/play/h?(\d+)/').firstMatch(href);
    return match?.group(1);
  }

  /// 封面优先取 img 的 background-image, 缺失时退回 data-img 的第一项.
  static String _parseCover(dynamic item) {
    final image = item.querySelector('img');
    if (image == null) {
      return '';
    }
    final fromStyle = _parseBackground(image.attributes['style'] ?? '');
    if (fromStyle.isNotEmpty) {
      return fromStyle;
    }
    final dataImg = (image.attributes['data-img'] ?? '')
        .split(',')
        .map((e) => e.trim())
        .firstWhere((e) => e.isNotEmpty, orElse: () => '');
    return dataImg.isNotEmpty ? dataImg : image.attributes['src'] ?? '';
  }

  static String _parseBackground(String style) {
    final match = RegExp(r'url\(([^)]+)\)').firstMatch(style);
    return match?.group(1)?.replaceAll(RegExp(r'''^["']|["']$'''), '').trim() ??
        '';
  }

  static int _parseCount(String text) {
    final match = RegExp(r'([\d,]+)').firstMatch(text);
    if (match == null) {
      return 0;
    }
    return int.tryParse(match.group(1)!.replaceAll(',', '')) ?? 0;
  }
}
