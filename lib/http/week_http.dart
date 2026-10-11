import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:tucao/common/constants.dart';
import 'package:tucao/models/video.dart';
import 'package:tucao/utils/http_util.dart';
import 'package:tucao/utils/logger.dart';

/// 新番时间表的一个分组.
class WeekGroup {
  const WeekGroup({required this.title, required this.list});

  /// 分组名, 取自站点标签: 周日到周六, 以及剧场与天朝.
  final String title;

  final List<VideoModel> list;
}

/// 首页的新番时间表.
///
/// 站点把九个分组 (周日到周六 + 剧场 + 天朝) 一次性渲染在首页里,
/// 由前端脚本切换显示, 因此这里抓首页解析, 不需要按分组分别请求.
abstract final class WeekHttp {
  /// 分组标题, 与站点标签顺序一致.
  static const titles = [
    '周日',
    '周一',
    '周二',
    '周三',
    '周四',
    '周五',
    '周六',
    '剧场',
    '天朝',
  ];

  static Future<List<WeekGroup>> fetch({CancelToken? cancelToken}) async {
    final response = await HttpUtil.dio.get(
      Constants.baseUrl,
      options: Options(headers: {'user-agent': Constants.desktopUserAgent}),
      cancelToken: cancelToken,
    );
    return parseHomeHtml(response.data.toString());
  }

  /// 解析首页里的新番时间表.
  ///
  /// 页面结构为 `div.xf_list` 下的九个 `ul`, 与 `div.xf_tabs` 的九个标签
  /// 一一对应; 每个 `ul` 里是若干 `div.item`.
  static List<WeekGroup> parseHomeHtml(String raw) {
    final document = html_parser.parse(raw);
    final lists = document.querySelectorAll('.xf_list ul');
    if (lists.isEmpty) {
      Log.w('首页里没有找到新番时间表');
      return const [];
    }

    final groups = <WeekGroup>[];
    for (var i = 0; i < lists.length; i++) {
      final title = i < titles.length ? titles[i] : '第 ${i + 1} 组';
      final list = <VideoModel>[];
      final seen = <String>{};
      for (final item in lists[i].querySelectorAll('.item')) {
        final link = item.querySelector('a.t') ?? item.querySelector('a');
        if (link == null) {
          continue;
        }
        final hid = _parseHid(link.attributes['href'] ?? '');
        if (hid == null || !seen.add(hid)) {
          continue;
        }
        final coverLink = item.querySelector('a.img') ?? link;
        list.add(
          VideoModel(
            hid: hid,
            title: link.text.trim(),
            cover: _parseBackground(coverLink.attributes['style'] ?? ''),
            playCount: _parseCount(
              item.querySelector('.i span')?.text ?? '',
            ),
            // 集数状态与题材标签模型里没有对应字段, 复用这两个文本字段承载.
            description: item.querySelector('.i b')?.text.trim() ?? '',
            keywords: item.querySelector('em')?.text.trim() ?? '',
          ),
        );
      }
      groups.add(WeekGroup(title: title, list: list));
    }
    Log.i('新番时间表解析完成, 共 ${groups.length} 组');
    return groups;
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
