import 'package:tucao/build_config.dart';

/// 主站域名的运行期配置.
///
/// 站点更换域名时可以在设置里改, 不必重新打包. 网络层与各接口在启动时
/// 按域名拼接地址, 因此修改后需要重启应用才生效.
abstract final class SiteHost {
  /// 默认主站域名.
  static const defaultHost = 'www.tucao.my';

  /// 用户设置的域名, 为空表示使用构建时或默认的域名.
  static String? _override;

  /// 构建时传入的域名, 见 `--dart-define=SITE`.
  static String get buildHost => BuildConfig.site;

  /// 当前生效的主站域名.
  static String get host =>
      _override ?? (buildHost.isEmpty ? defaultHost : buildHost);

  /// 当前生效的主站地址, 末尾带斜杠.
  static String get baseUrl => 'https://$host/';

  /// 设置运行期覆盖的域名, 传空或非法值时回到构建时或默认的域名.
  static void setOverride(String? raw) {
    final text = raw?.trim() ?? '';
    if (text.isEmpty) {
      _override = null;
      return;
    }
    _override = normalize(text) ?? _override;
  }

  /// 把用户输入整理成主机名, 非法输入返回 null.
  ///
  /// 接受 `www.tucao.my`, `https://www.tucao.my/`, `WWW.TUCAO.MY` 等写法,
  /// 去掉协议, 路径, 空白与大小写差异; 允许带端口.
  static String? normalize(String raw) {
    var text = raw.trim();
    text = text.replaceFirst(RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://'), '');
    final slash = text.indexOf('/');
    if (slash >= 0) {
      text = text.substring(0, slash);
    }
    text = text.trim().toLowerCase();
    if (text.isEmpty) {
      return null;
    }

    var hostPart = text;
    var portPart = '';
    final colon = text.lastIndexOf(':');
    if (colon >= 0) {
      hostPart = text.substring(0, colon);
      final port = text.substring(colon + 1);
      if (!RegExp(r'^\d{1,5}$').hasMatch(port)) {
        return null;
      }
      final value = int.parse(port);
      if (value < 1 || value > 65535) {
        return null;
      }
      portPart = ':$value';
    }

    final label = RegExp(r'^[a-z0-9]([a-z0-9-]*[a-z0-9])?$');
    final labels = hostPart.split('.');
    if (labels.length < 2 || !labels.every(label.hasMatch)) {
      return null;
    }
    return '$hostPart$portPart';
  }
}
