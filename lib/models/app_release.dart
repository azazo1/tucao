/// GitHub Release 中更新提示需要的信息.
///
/// 应用通过 GitHub Release 分发, 发布页里放着各架构的 APK,
/// 因此这里只保留标签, 正文与发布页地址, 不解析具体产物.
class AppRelease {
  const AppRelease({
    required this.tagName,
    required this.name,
    required this.body,
    required this.pageUrl,
    this.prerelease = false,
  });

  /// 标签名, 形如 `v1.2.0`.
  final String tagName;

  /// Release 标题, 未填写时与标签相同.
  final String name;

  /// Release 正文, 即该版本的发布说明.
  final String body;

  /// 发布页面地址, 用户在页面里选择对应架构的 APK.
  final String pageUrl;

  /// 是否为预发布版本.
  final bool prerelease;

  /// 从 GitHub API 的 release json 构造, 缺字段时返回 null.
  static AppRelease? fromJson(Map<String, dynamic> json) {
    final tag = json['tag_name'];
    final url = json['html_url'];
    if (tag is! String || tag.isEmpty || url is! String || url.isEmpty) {
      return null;
    }
    final name = json['name'];
    final body = json['body'];
    return AppRelease(
      tagName: tag,
      name: name is String && name.isNotEmpty ? name : tag,
      body: body is String ? body : '',
      pageUrl: url,
      prerelease: json['prerelease'] == true,
    );
  }
}
