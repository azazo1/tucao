/// 一个国内镜像源.
///
/// 前缀直接拼在原始 GitHub 地址前面, 由镜像站转发到 github.com,
/// 因此这里只保存前缀与开关, 不保存任何请求模板.
class UpdateMirror {
  const UpdateMirror({required this.prefix, this.enabled = true});

  /// 镜像前缀, 形如 `https://gh-proxy.com`, 不带末尾斜杠.
  final String prefix;

  /// 是否参与下载.
  final bool enabled;

  /// 内置默认源, 用户删光之后可以用它恢复.
  static const builtin = <UpdateMirror>[
    UpdateMirror(prefix: 'https://gh-proxy.com'),
  ];

  /// 前缀对应的下载地址.
  String urlFor(String url) => '$prefix/$url';

  UpdateMirror copyWith({bool? enabled}) =>
      UpdateMirror(prefix: prefix, enabled: enabled ?? this.enabled);

  Map<String, Object?> toJson() => {'prefix': prefix, 'enabled': enabled};

  /// 从存储的 json 还原, 前缀不合法时返回 null.
  ///
  /// 缺少 enabled 时按启用处理, 旧数据或手改过的配置都能读.
  static UpdateMirror? fromJson(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final prefix = raw['prefix'];
    if (prefix is! String) {
      return null;
    }
    final normalized = normalizePrefix(prefix);
    if (validatePrefix(normalized) != null) {
      return null;
    }
    return UpdateMirror(prefix: normalized, enabled: raw['enabled'] != false);
  }

  /// 去掉首尾空白与末尾斜杠, 让前缀可以直接拼接地址.
  static String normalizePrefix(String raw) =>
      raw.trim().replaceFirst(RegExp(r'/+$'), '');

  /// 校验用户输入的前缀, 可用时返回 null, 否则返回提示文案.
  static String? validatePrefix(String raw) {
    final text = normalizePrefix(raw);
    if (text.isEmpty) {
      return '请填写镜像前缀';
    }
    final uri = Uri.tryParse(text);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return '前缀要写成完整的地址, 例如 https://gh-proxy.com';
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      return '只支持 http 或 https 前缀';
    }
    if (uri.hasQuery || uri.hasFragment) {
      return '前缀里不要带查询参数或锚点';
    }
    return null;
  }
}
