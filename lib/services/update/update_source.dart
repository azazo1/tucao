import 'package:tucao/utils/storage_pref.dart';

/// 更新包的下载源.
///
/// 应用经 GitHub Release 分发, 直连 github.com 在部分网络下很慢甚至不可用,
/// 因此允许改走第三方 GitHub 加速镜像. 镜像只做转发, 安装包内容与官方一致,
/// 下载结果仍按发布记录里的大小与 ZIP 头校验, 不额外信任镜像站.
enum UpdateSource {
  /// 先试国内镜像, 全部失败再改用 GitHub 官方源.
  auto('自动', '先走国内镜像, 失败时自动改用 GitHub 官方源'),

  /// 只走国内镜像, 按顺序尝试可用的镜像站.
  mirror('国内镜像', '通过 GitHub 加速站下载, 直连 github.com 不通时更稳'),

  /// 只走 GitHub 官方源.
  github('GitHub 官方源', '直接连接 github.com, 不经过任何加速站');

  const UpdateSource(this.label, this.description);

  /// 设置项里的名称.
  final String label;

  /// 设置项里的说明.
  final String description;

  /// 设置里保存的值, 没有保存过或读了不认识的值时按自动处理.
  static UpdateSource get saved =>
      UpdateSource.values.asNameMap()[Pref.updateSource] ?? UpdateSource.auto;
}

/// 下载地址的候选列表.
abstract final class UpdateSources {
  /// 按顺序尝试的国内镜像站.
  ///
  /// 前缀直接拼在原始 GitHub 地址前面, 由镜像站转发到 github.com.
  /// 这里只放实测可用的站点, 某个站失效时换掉一条即可.
  static const mirrors = <String>[
    'https://gh-proxy.com',
    'https://ghproxy.net',
  ];

  /// [downloadUrl] 在指定下载源下要依次尝试的地址.
  ///
  /// 自动与国内镜像排在前面, GitHub 官方源排在最后, 只有一个候选时
  /// 就是原地址. 不是 github.com 的地址没有可套的镜像, 只返回原地址.
  static List<Uri> candidates({
    required String downloadUrl,
    required UpdateSource source,
  }) {
    final official = Uri.tryParse(downloadUrl);
    // 空串也会解析成没有 scheme 的 Uri, 这种地址请求不出去.
    if (official == null || !official.hasScheme) {
      return const [];
    }
    if (!_isGithub(official)) {
      return [official];
    }
    return [
      if (source != UpdateSource.github)
        for (final prefix in mirrors) Uri.parse('$prefix/$downloadUrl'),
      if (source != UpdateSource.mirror) official,
    ];
  }

  /// 只对 github.com 的地址套镜像, 其他地址原样请求.
  static bool _isGithub(Uri uri) =>
      uri.scheme == 'https' && uri.host == 'github.com';
}
