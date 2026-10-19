import 'package:path/path.dart' as path;

/// GitHub Release 里的一个产物文件.
///
/// 发布页里放着各架构的 APK 与校验文件, 更新流程只关心其中的 APK,
/// 因此这里保留文件名, 字节数与下载地址即可.
class ReleaseAsset {
  const ReleaseAsset({
    required this.name,
    required this.size,
    required this.downloadUrl,
  });

  /// 产物文件名, 形如 `tucao-1.3.0-android-arm64-v8a.apk`.
  final String name;

  /// 文件字节数, 接口没有给出时为 -1.
  final int size;

  /// 直接下载地址.
  final String downloadUrl;

  /// 从 GitHub API 的 release asset json 构造, 缺字段或名字不可用时返回 null.
  static ReleaseAsset? fromJson(Map<String, dynamic> json) {
    final name = json['name'];
    final url = json['browser_download_url'];
    if (name is! String || !isSafeName(name) || url is! String || url.isEmpty) {
      return null;
    }
    final size = json['size'];
    return ReleaseAsset(
      name: name,
      size: size is num ? size.toInt() : -1,
      downloadUrl: url,
    );
  }

  /// 产物名能否直接当作文件名使用.
  ///
  /// 名字来自网络, 因此要求它不带路径分隔, 不以点开头, 且后缀是 apk.
  static bool isSafeName(String name) =>
      name.isNotEmpty &&
      name == path.basename(name) &&
      !name.contains(r'\') &&
      !name.startsWith('.') &&
      name.toLowerCase().endsWith('.apk');

  /// 是否为某个 ABI 的安装包, 例如 `arm64-v8a`.
  bool isApkFor(String abi) =>
      abi.isNotEmpty &&
      name.toLowerCase().endsWith('-${abi.toLowerCase()}.apk');

  /// 按设备 ABI 的优先顺序从产物里挑出对应的安装包, 没有匹配时返回 null.
  ///
  /// 只认发布里真实存在的产物, 因此设备报出没发布的架构时一并返回 null,
  /// 由调用方退回到发布页.
  static ReleaseAsset? pickFor(List<ReleaseAsset> assets, List<String> abis) {
    for (final abi in abis) {
      for (final asset in assets) {
        if (asset.isApkFor(abi)) {
          return asset;
        }
      }
    }
    return null;
  }

  /// 解析产物数组, 结构不符的条目直接丢掉, 不影响版本提示本身.
  static List<ReleaseAsset> listFrom(Object? raw) {
    if (raw is! List) {
      return const [];
    }
    final assets = <ReleaseAsset>[];
    for (final entry in raw) {
      if (entry is! Map) {
        continue;
      }
      final asset = fromJson(entry.cast<String, dynamic>());
      if (asset != null) {
        assets.add(asset);
      }
    }
    return assets;
  }

  /// 产物体积的展示文案, 接口没有给出大小时说明未知.
  String get sizeText {
    if (size <= 0) {
      return '大小未知';
    }
    final megabytes = size / (1024 * 1024);
    if (megabytes >= 1) {
      return '${megabytes.toStringAsFixed(1)} MB';
    }
    return '${(size / 1024).toStringAsFixed(0)} KB';
  }
}
