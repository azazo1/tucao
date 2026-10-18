import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:tucao/common/constants.dart';
import 'package:tucao/utils/http_util.dart';

/// 官网首页广告位里的一条广告.
class AdItem {
  const AdItem({required this.imageUrl, required this.linkUrl});

  /// 广告图片, 站内相对地址会补全.
  final String imageUrl;

  /// 点击后要打开的目标地址.
  final String linkUrl;
}

/// 首页广告位.
///
/// 官方客户端的首页会把站点 `header_rmb` 里的多条广告图依次展示出来,
/// 这里按同样的来源取出全部广告, 不在客户端写死推广地址.
abstract final class AdHttp {
  /// 拉取首页广告位里的全部广告.
  static Future<List<AdItem>> fetchHomeAds({CancelToken? cancelToken}) async {
    final response = await HttpUtil.dio.get(
      Constants.baseUrl,
      cancelToken: cancelToken,
      options: Options(headers: {'user-agent': Constants.desktopUserAgent}),
    );
    return parseHomeAds(response.data.toString());
  }

  /// 解析首页广告位里的全部广告.
  static List<AdItem> parseHomeAds(String raw) {
    final document = html_parser.parse(raw);
    final items = <AdItem>[];
    final seen = <String>{};
    for (final anchor in document.querySelectorAll('.header_rmb a[href]')) {
      final href = anchor.attributes['href']?.trim() ?? '';
      final image = anchor.querySelector('img')?.attributes['src']?.trim() ?? '';
      if (href.isEmpty || image.isEmpty || !seen.add(href)) {
        continue;
      }
      final uri = Uri.tryParse(href);
      if (uri == null || (uri.hasScheme && uri.scheme != 'http' && uri.scheme != 'https')) {
        continue;
      }
      items.add(
        AdItem(imageUrl: _absolute(image), linkUrl: _absolute(href)),
      );
    }
    return items;
  }

  static String _absolute(String raw) {
    final uri = Uri.tryParse(raw);
    if (uri == null || uri.hasScheme) {
      return raw;
    }
    return Uri.parse(Constants.baseUrl).resolve(raw).toString();
  }
}
