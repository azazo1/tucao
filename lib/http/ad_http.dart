import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:tucao/common/constants.dart';
import 'package:tucao/utils/http_util.dart';

/// 首页广告位.
///
/// 官方客户端从站点首页的 banner/广告位里取图片与链接, 这里沿用同样的思路,
/// 读取 `header_rmb` 里的第一条广告链接, 不在客户端写死推广地址.
abstract final class AdHttp {
  /// 拉取首页广告位里的第一条链接.
  static Future<String?> fetchHomeAdLink({CancelToken? cancelToken}) async {
    final response = await HttpUtil.dio.get(
      Constants.baseUrl,
      cancelToken: cancelToken,
      options: Options(headers: {'user-agent': Constants.desktopUserAgent}),
    );
    return parseHomeAdLink(response.data.toString());
  }

  /// 解析首页广告位里的第一条链接.
  static String? parseHomeAdLink(String raw) {
    final document = html_parser.parse(raw);
    final anchor = document.querySelector('.header_rmb a[href]');
    final href = anchor?.attributes['href']?.trim() ?? '';
    if (href.isEmpty) {
      return null;
    }
    final uri = Uri.tryParse(href);
    if (uri == null) {
      return null;
    }
    if (uri.scheme == 'http' || uri.scheme == 'https') {
      return href;
    }
    if (uri.hasScheme) {
      return null;
    }
    return Uri.parse(Constants.baseUrl).resolve(href).toString();
  }
}
