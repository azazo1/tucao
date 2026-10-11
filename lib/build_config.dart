/// 编译期注入的构建参数, 见 build.just 中的 dart-define 定义.
abstract final class BuildConfig {
  /// 应用版本号, 与 pubspec.yaml 同步维护.
  static const String version = String.fromEnvironment(
    'VERSION',
    defaultValue: '1.0.0',
  );

  /// 接口请求使用的站点, 可在构建时切换备用域名.
  static const String? site = String.fromEnvironment('SITE') == ''
      ? null
      : String.fromEnvironment('SITE');

  /// 是否输出调试日志.
  static const bool debugLog = bool.fromEnvironment('DEBUG_LOG');
}
