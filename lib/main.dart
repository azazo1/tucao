import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tucao/router/app_pages.dart';
import 'package:tucao/router/routes.dart';
import 'package:tucao/common/style.dart';
import 'package:tucao/common/site_host.dart';
import 'package:tucao/http/init.dart';
import 'package:tucao/services/account_service.dart';
import 'package:tucao/services/ad_service.dart';
import 'package:tucao/services/download/download_service.dart';
import 'package:tucao/services/download/download_transport.dart';
import 'package:tucao/services/history_service.dart';
import 'package:tucao/services/favorite_service.dart';
import 'package:tucao/services/message_count_service.dart';
import 'package:tucao/services/site_favorite_service.dart';
import 'package:tucao/services/theme_service.dart';
import 'package:tucao/services/update/update_download_service.dart';
import 'package:tucao/services/update/update_transport.dart';
import 'package:tucao/services/vip_service.dart';
import 'package:tucao/utils/logger.dart';
import 'package:tucao/utils/http_util.dart';
import 'package:tucao/utils/storage.dart';
import 'package:tucao/utils/storage_pref.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:media_kit/media_kit.dart';

Future<void> main() async {
  final start = DateTime.now();
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  await GStorage.init();
  // 域名在设置里改过时, 网络层与页面地址都按它拼接, 因此必须在初始化前读入.
  SiteHost.setOverride(Pref.siteHost);
  await HttpInit.init();
  Get.put(ThemeService());
  Get.put(AccountService());
  Get.put(AdService());
  Get.put(HistoryService());
  // 评论区的破会员标记, 只在内存里攒, 不做持久化.
  Get.put(VipService());
  Get.put(FavoriteService(), permanent: true);
  // 站点追番在播放页与我的收藏页共用, 拉取时机由页面决定.
  Get.put(SiteFavoriteService(), permanent: true);
  // 未读私信与评论数挂在「我的」入口上, 需要登录态, 取数时机由主框架决定.
  Get.put(MessageCountService(), permanent: true);
  final downloads = Get.put(
    DownloadService(transport: DioDownloadTransport(HttpUtil.dio)),
    permanent: true,
  );
  try {
    await downloads.initialize();
  } catch (error) {
    // 外部存储不可用时其他页面照常启动, 缓存页提供重试.
    Log.w('外部缓存目录未就绪: $error');
  }
  // 更新包另走一条道: 产物是 apk, 校验与目录都和媒体缓存不同,
  // 也不共用站点客户端, 免得把 cookie 带去 GitHub.
  Get.put(
    UpdateDownloadService(transport: DioUpdateTransport()),
    permanent: true,
  );

  Log.i('应用启动完成, 耗时 ${DateTime.now().difference(start).inMilliseconds}ms');
  runApp(const TucaoApp());
}

class TucaoApp extends StatelessWidget {
  const TucaoApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeService = ThemeService.instance;
    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        return Obx(() {
          final useDynamic = themeService.useDynamicColor.value;
          final seed = themeService.seedColor.value;
          final lightScheme = useDynamic && seed == null ? lightDynamic : null;
          final darkScheme = useDynamic && seed == null ? darkDynamic : null;
          return GetMaterialApp(
            title: '吐槽',
            debugShowCheckedModeBanner: false,
            themeMode: switch (themeService.themeMode.value) {
              1 => ThemeMode.light,
              2 => ThemeMode.dark,
              _ => ThemeMode.system,
            },
            theme: _theme(lightScheme, seed, Brightness.light),
            darkTheme: _theme(darkScheme, seed, Brightness.dark),
            initialRoute: Routes.main,
            getPages: AppPages.pages,
            defaultTransition: Transition.cupertino,
            transitionDuration: const Duration(milliseconds: 250),
            locale: const Locale('zh', 'CN'),
            fallbackLocale: const Locale('zh', 'CN'),
          );
        });
      },
    );
  }

  /// 自定义种子色优先, 其次系统取色, 最后回落到站点默认色.
  ThemeData _theme(
    ColorScheme? dynamicScheme,
    int? seed,
    Brightness brightness,
  ) {
    if (seed != null) {
      final scheme = ColorScheme.fromSeed(
        seedColor: Color(seed),
        brightness: brightness,
      );
      return brightness == Brightness.dark
          ? Style.dark(scheme)
          : Style.light(scheme);
    }
    return brightness == Brightness.dark
        ? Style.dark(dynamicScheme)
        : Style.light(dynamicScheme);
  }
}
