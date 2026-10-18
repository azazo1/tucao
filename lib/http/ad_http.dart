import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:tucao/common/constants.dart';
import 'package:tucao/http/api_path.dart';
import 'package:tucao/utils/http_util.dart';
import 'package:tucao/utils/logger.dart';

/// 官网首页广告位里的一条广告.
class AdItem {
  const AdItem({
    required this.adId,
    required this.loggedIn,
    required this.imageUrl,
    required this.linkUrl,
  });

  /// 广告位 id, 例如 t36; 站点没挂上报脚本时为 null.
  final String? adId;

  /// 站点渲染这条广告时访客是否已经登录.
  ///
  /// 站点只给登录访客挂点击上报, 未登录的点击不计入统计, 应用照此处理.
  final bool loggedIn;

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
  /// 广告位上的上报脚本, 形如 `adClick('t36', 0)`, 第二个参数是登录标记.
  ///
  /// 没挂脚本的广告位照样展示, 只是点击不计入站点统计.
  static final _adClickPattern = RegExp(
    '''adClick\\(\\s*['"]([^'"]*)['"]\\s*,\\s*([01])\\s*\\)''',
  );

  /// 拉取首页广告位里的全部广告.
  static Future<List<AdItem>> fetchHomeAds({CancelToken? cancelToken}) async {
    final response = await HttpUtil.dio.get(
      Constants.baseUrl,
      cancelToken: cancelToken,
      options: Options(headers: {'user-agent': Constants.desktopUserAgent}),
    );
    return parseHomeAds(response.data.toString());
  }

  /// 上报一次广告点击.
  ///
  /// 打的是站点页面里 `adClick` 用的同一个地址, UA 也与抓广告位时一致,
  /// 站点据此记积分与续命. 上报失败只记日志: 统计不该挡住用户看广告.
  static Future<void> reportClick(String adId) async {
    final url = ApiPath.adClickUrl(
      adId,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
    try {
      final response = await HttpUtil.dio.get(
        url,
        options: Options(headers: {'user-agent': Constants.desktopUserAgent}),
      );
      Log.i('广告点击上报 $adId 返回 ${response.data}');
    } catch (error, stackTrace) {
      Log.e('广告点击上报失败 $adId', error: error, stackTrace: stackTrace);
    }
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
      final (adId, loggedIn) = _parseAdClick(anchor.attributes['onclick'] ?? '');
      items.add(
        AdItem(
          adId: adId,
          loggedIn: loggedIn,
          imageUrl: _absolute(image),
          linkUrl: _absolute(href),
        ),
      );
    }
    return items;
  }

  /// 从 onclick 里取出广告位 id 与登录标记.
  static (String?, bool) _parseAdClick(String onclick) {
    final match = _adClickPattern.firstMatch(onclick);
    if (match == null) {
      return (null, false);
    }
    final adId = match.group(1)?.trim() ?? '';
    return (adId.isEmpty ? null : adId, match.group(2) == '1');
  }

  static String _absolute(String raw) {
    final uri = Uri.tryParse(raw);
    if (uri == null || uri.hasScheme) {
      return raw;
    }
    return Uri.parse(Constants.baseUrl).resolve(raw).toString();
  }
}
