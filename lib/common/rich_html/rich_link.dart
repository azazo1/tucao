import 'package:get/get.dart';
import 'package:tucao/router/routes.dart';
import 'package:tucao/utils/logger.dart';
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
    final match = RegExp(r'^/play/([hdu])(\d+)/?$').firstMatch(uri.path);
    if (match != null) {
      final id = match.group(2)!;
      Log.i('正文链接在应用内打开: ${uri.path}');
      switch (match.group(1)) {
        case 'h':
          Get.toNamed(Routes.video, parameters: {'hid': id});
        case 'd':
          Get.toNamed(Routes.article, parameters: {'hid': id});
        default:
          Get.toNamed(Routes.space, parameters: {'uid': id});
      }
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
