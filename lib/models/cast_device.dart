/// 局域网里发现的可投屏设备.
///
/// 只保存发现阶段得到的必要信息, 控制地址等细节在连接时从设备描述里解析,
/// 避免把可能变化的地址缓存进列表.
class CastDevice {
  const CastDevice({
    required this.udn,
    required this.name,
    required this.location,
    this.manufacturer = '',
    this.modelName = '',
  });

  /// 设备唯一标识, 来自设备描述的 UDN.
  final String udn;

  /// 展示名, 来自设备描述的 friendlyName.
  final String name;

  /// 设备描述地址, 控制地址按它解析.
  final String location;

  final String manufacturer;

  final String modelName;

  /// 设备所在的主机地址, 用于提示与日志.
  String get host => Uri.tryParse(location)?.host ?? '';

  /// 列表里的第二行说明.
  String get subtitle {
    final parts = [
      if (modelName.isNotEmpty) modelName,
      if (manufacturer.isNotEmpty) manufacturer,
      if (host.isNotEmpty) host,
    ];
    return parts.join(' · ');
  }

  @override
  String toString() => 'CastDevice($name, $location)';
}
