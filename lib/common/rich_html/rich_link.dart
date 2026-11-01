import 'package:tucao/router/site_navigation.dart';
import 'package:tucao/utils/logger.dart';
import 'package:tucao/utils/site_route.dart';
import 'package:tucao/utils/site_url.dart';
import 'package:url_launcher/url_launcher.dart';

/// 打开正文里的链接.
///
/// 站内的视频, 档案与个人空间直接进对应页面, 其余地址交给系统处理,
/// 邮箱链接会唤起邮件应用.
Future<void> openRichLink(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null) {
    return;
  }
  if (isSiteUrl(url)) {
    final route = siteRouteOf(uri);
    if (route != null) {
      Log.i('正文链接在应用内打开: ${uri.path}');
      openSiteRoute(route);
      return;
    }
  }
  try {
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened) {
      Log.w('系统没有处理正文链接: $url');
    }
  } catch (e, stackTrace) {
    Log.e('打开正文链接失败', error: e, stackTrace: stackTrace);
  }
}
