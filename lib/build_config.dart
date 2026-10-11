/// 编译期注入的构建参数, 由 scripts/dist.py 与 ci 通过 --dart-define 传入.
abstract final class BuildConfig {
  /// 构建版本号.
  ///
  /// 发布构建由 PROJECT_BUILD_VERSION 注入, 形如 v1.2.3 或 v1.2.3-a1b2c3d;
  /// 日常开发构建不注入, 显示为 dev-build.
  static const String buildVersion = String.fromEnvironment(
    'BUILD_VERSION',
    defaultValue: 'dev-build',
  );

  /// 接口请求使用的站点, 可在构建时切换备用域名.
  static const String site = String.fromEnvironment('SITE');

  /// 是否输出调试日志.
  static const bool debugLog = bool.fromEnvironment('DEBUG_LOG');
}
