import 'dart:io';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:tucao/utils/http_util.dart';
import 'package:tucao/utils/logger.dart';

/// 网络层初始化.
///
/// 站点依赖 cookie 维持登录态, 因此把 cookie 持久化到应用目录,
/// 重启后仍然保持登录.
abstract final class HttpInit {
  static late PersistCookieJar cookieJar;

  static Future<void> init() async {
    final dir = await getApplicationSupportDirectory();
    final cookiePath = path.join(dir.path, 'cookie');
    final cookieDir = Directory(cookiePath);
    if (!cookieDir.existsSync()) {
      await cookieDir.create(recursive: true);
    }
    cookieJar = PersistCookieJar(
      ignoreExpires: true,
      storage: FileStorage(cookiePath),
    );
    HttpUtil.init(cookieInterceptor: CookieManager(cookieJar));
    Log.i('网络层初始化完成, cookie 目录: $cookiePath');
  }

  /// 清除全部 cookie, 用于退出登录.
  static Future<void> clearCookie() async {
    await cookieJar.deleteAll();
    Log.i('已清除全部 cookie');
  }
}
