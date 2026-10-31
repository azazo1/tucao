import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:tucao/common/constants.dart';
import 'package:tucao/utils/http_util.dart';
import 'package:tucao/utils/logger.dart';
import 'package:tucao/utils/site_url.dart';

/// 首页轮转区里的一篇站务文章, 如公告与情报.
class SiteNotice {
  const SiteNotice({
    required this.hid,
    required this.title,
    required this.summary,
    required this.cover,
  });

  /// 档案条目编号, 用于打开详情.
  final String hid;

  final String title;

  /// 摘要, 站点截断过, 可能为空.
  final String summary;

  /// 竖版大图的绝对地址, 可能为空.
  final String cover;
}

/// 首页轮转区数据源.
///
/// 轮转区 `.focus .slide` 里混着站务文章与新番推荐, 文章链接形如
/// `/play/d7241/`, 视频是 `/play/h4107879/`. 新番推荐与时间表重复,
/// 这里只取文章.
abstract final class SiteNoticeHttp {
  static final _articleHref = RegExp(r'/play/d(\d+)/');

  static Future<List<SiteNotice>> fetch({CancelToken? cancelToken}) async {
    final response = await HttpUtil.dio.get(
      Constants.baseUrl,
      options: Options(headers: {'user-agent': Constants.desktopUserAgent}),
      cancelToken: cancelToken,
    );
    return parseHomeHtml(response.data.toString());
  }

  /// 解析首页里的轮转区, 按页面顺序返回, 同一篇只保留一次.
  static List<SiteNotice> parseHomeHtml(String raw) {
    final document = html_parser.parse(raw);
    final list = <SiteNotice>[];
    final seen = <String>{};
    for (final slide in document.querySelectorAll('.focus .slide')) {
      final link = slide.querySelector('a.t');
      final match = _articleHref.firstMatch(link?.attributes['href'] ?? '');
      if (link == null || match == null) {
        continue;
      }
      final hid = match.group(1)!;
      final title = link.querySelector('div')?.text.trim() ?? '';
      if (title.isEmpty || !seen.add(hid)) {
        continue;
      }
      list.add(
        SiteNotice(
          hid: hid,
          title: title,
          summary: link.querySelector('p')?.text.trim() ?? '',
          cover: absoluteSiteUrl(
            slide.querySelector('a.i img')?.attributes['src'] ?? '',
          ),
        ),
      );
    }
    Log.i('首页轮转区解析完成, 站务文章 ${list.length} 条');
    return list;
  }
}
