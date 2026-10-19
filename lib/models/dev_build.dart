import 'package:tucao/models/release_asset.dart';
import 'package:tucao/utils/version.dart';

/// CI 预发布 `dev-latest` 里最新一次分支构建.
///
/// 分支构建的说明与产物会被后续推送覆盖, tag 本身停在首次构建,
/// 因此这里的版本号取自 release 说明, 不看 tag 指向的提交.
class DevBuild {
  const DevBuild({
    required this.buildVersion,
    required this.body,
    required this.pageUrl,
    this.assets = const [],
  });

  /// CI 注入的构建版本, 形如 `v1.2.3-a1b2c3d`; 说明里读不到时为空.
  final String buildVersion;

  /// release 说明原文.
  final String body;

  /// 发布页地址, 没有匹配的安装包时留给用户在页面里自己挑.
  final String pageUrl;

  /// 本次构建提供的产物文件.
  final List<ReleaseAsset> assets;

  /// 按设备 ABI 的优先顺序挑出对应的安装包, 没有匹配时返回 null.
  ReleaseAsset? apkFor(List<String> abis) => ReleaseAsset.pickFor(assets, abis);

  /// 从 GitHub API 的 release json 构造, 缺少发布页地址时返回 null.
  static DevBuild? fromJson(Map<String, dynamic> json) {
    final url = json['html_url'];
    if (url is! String || url.isEmpty) {
      return null;
    }
    final body = json['body'];
    final name = json['name'];
    final text = body is String ? body : '';
    return DevBuild(
      buildVersion:
          _versionIn(text) ?? _versionIn(name is String ? name : '') ?? '',
      body: text,
      pageUrl: url,
      assets: ReleaseAsset.listFrom(json['assets']),
    );
  }

  /// 本机当前构建相对 CI 上这一份的状态.
  ///
  /// 基础版本相同时按提交区分: 分支构建的版本号带 7 位短 hash,
  /// 只要版本串不同就说明 CI 上的是另一次构建.
  DevBuildStatus statusFor(String current) {
    final mine = _normalize(current);
    final ci = _normalize(buildVersion);
    if (mine.isEmpty || ci.isEmpty || mine == 'dev-build') {
      return DevBuildStatus.unknown;
    }
    if (mine == ci) {
      return DevBuildStatus.latest;
    }
    if (Version.compare(mine, ci) > 0) {
      return DevBuildStatus.localNewer;
    }
    return DevBuildStatus.outdated;
  }

  /// 说明里的构建版本行比标题更稳定, 标题只在说明缺行时兜底.
  static String? _versionIn(String text) {
    final match =
        _noteVersion.firstMatch(text) ?? _titleVersion.firstMatch(text);
    return match?.group(1);
  }

  static String _normalize(String raw) {
    var text = raw.trim();
    if (text.startsWith('v') || text.startsWith('V')) {
      text = text.substring(1);
    }
    return text;
  }

  /// 说明里由 CI 写出的构建版本行, 版本号包在反引号里.
  static final _noteVersion = RegExp(r'构建版本:\s*`([^`]+)`');

  /// release 标题, 形如 `吐槽 最新构建 v1.2.3-a1b2c3d`.
  static final _titleVersion = RegExp(r'最新构建\s+(\S+)');
}

/// 本机当前构建相对 CI 开发版的状态.
enum DevBuildStatus {
  /// 版本串一致, 本机就是 CI 上这一份.
  latest,

  /// CI 上有另一次构建.
  outdated,

  /// 本机的基础版本比 CI 的高, 不是旧构建.
  localNewer,

  /// 无法比较, 例如本地构建没有注入版本号.
  unknown,
}
