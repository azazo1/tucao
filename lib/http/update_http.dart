import 'package:dio/dio.dart';
import 'package:tucao/models/app_release.dart';

/// GitHub Release 查询.
///
/// 应用经 GitHub Release 分发, 这里直接查最新一次正式发布.
/// 该接口在 api.github.com, 不需要站点 cookie, 因此不复用 [HttpUtil] 的客户端.
abstract final class UpdateHttp {
  /// 仓库的最新正式发布接口.
  static const latestUrl =
      'https://api.github.com/repos/azazo1/tucao/releases/latest';

  static final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 8),
      // GitHub 要求请求带上 UA, 否则直接返回 403.
      headers: {
        'Accept': 'application/vnd.github+json',
        'User-Agent': 'tucao-android',
      },
    ),
  );

  /// 拉取最新正式发布.
  static Future<AppRelease?> fetchLatest() async {
    final response = await _dio.get<Map<String, dynamic>>(latestUrl);
    return parseRelease(response.data);
  }

  /// 解析最新发布的响应, 结构不合法或不是正式版本时返回 null.
  static AppRelease? parseRelease(Map<String, dynamic>? data) {
    if (data == null) {
      return null;
    }
    final release = AppRelease.fromJson(data);
    if (release == null || release.prerelease) {
      return null;
    }
    return release;
  }
}
