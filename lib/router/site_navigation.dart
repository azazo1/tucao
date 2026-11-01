import 'package:get/get.dart';
import 'package:tucao/router/routes.dart';
import 'package:tucao/utils/site_route.dart';

/// 打开站内地址对应的应用内页面.
///
/// 富文本里的链接与搜索栏粘贴的地址共用这一套跳转, 页面只认路径,
/// 查询串与多余的锚点都不带过去.
void openSiteRoute(SiteRoute route) {
  switch (route.kind) {
    case SiteRouteKind.video:
      Get.toNamed(
        Routes.video,
        parameters: {
          'hid': route.id,
          if (route.part case final part?) 'part': part.toString(),
        },
      );
    case SiteRouteKind.article:
      Get.toNamed(Routes.article, parameters: {'hid': route.id});
    case SiteRouteKind.space:
      Get.toNamed(Routes.space, parameters: {'uid': route.id});
  }
}
