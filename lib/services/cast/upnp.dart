// UPnP 与 DLNA 的报文拼装与解析.
//
// 这里只放纯函数, 不碰网络, 便于用固定报文做单元测试.

import 'dart:convert';

import 'package:xml/xml.dart';

const String ssdpGroup = '239.255.255.250';
const int ssdpPort = 1900;

/// 渲染设备类型, M-SEARCH 按它搜索.
const String mediaRendererType = 'urn:schemas-upnp-org:device:MediaRenderer:1';

const String avTransportType =
    'urn:schemas-upnp-org:service:AVTransport:1';
const String renderingControlType =
    'urn:schemas-upnp-org:service:RenderingControl:1';

/// 电视普遍要求的 DLNA 能力声明, 缺了部分设备会拒绝播放.
const String _protocolInfoSuffix =
    'DLNA.ORG_OP=01;DLNA.ORG_CI=0;'
    'DLNA.ORG_FLAGS=01700000000000000000000000000000';

/// M-SEARCH 请求报文.
String buildMsearch({String searchTarget = mediaRendererType, int mx = 2}) {
  return 'M-SEARCH * HTTP/1.1\r\n'
      'HOST: $ssdpGroup:$ssdpPort\r\n'
      'MAN: "ssdp:discover"\r\n'
      'MX: $mx\r\n'
      'ST: $searchTarget\r\n'
      '\r\n';
}

/// 把响应头拆成小写键的表.
Map<String, String> parseHeaders(String text) {
  final headers = <String, String>{};
  for (final line in const LineSplitter().convert(text)) {
    final index = line.indexOf(':');
    if (index <= 0) {
      continue;
    }
    headers[line.substring(0, index).trim().toLowerCase()] =
        line.substring(index + 1).trim();
  }
  return headers;
}

/// 一条 SSDP 搜索响应.
class SsdpResponse {
  const SsdpResponse({required this.st, required this.usn, required this.location});

  final String st;
  final String usn;
  final String location;
}

/// 解析 M-SEARCH 的响应, 不是 200 或者缺少 LOCATION 时返回空.
SsdpResponse? parseSsdpResponse(String text) {
  final firstLine = text.split('\r\n').first.toUpperCase();
  if (!firstLine.startsWith('HTTP/1.1 200')) {
    return null;
  }
  final headers = parseHeaders(text);
  final location = headers['location'] ?? '';
  if (location.isEmpty) {
    return null;
  }
  return SsdpResponse(
    st: headers['st'] ?? '',
    usn: headers['usn'] ?? '',
    location: location,
  );
}

/// 设备描述里的有用信息.
class DeviceDescription {
  const DeviceDescription({
    required this.udn,
    required this.name,
    required this.deviceType,
    required this.services,
    this.manufacturer = '',
    this.modelName = '',
  });

  final String udn;
  final String name;
  final String deviceType;
  final String manufacturer;
  final String modelName;

  /// 服务类型到控制地址的映射, 地址已经补全成绝对地址.
  final Map<String, String> services;

  /// 是否具备播放能力: 设备类型是渲染器, 或者至少提供了 AVTransport.
  bool get isMediaRenderer =>
      deviceType.toLowerCase().contains('mediarenderer') ||
      services.containsKey(avTransportType);

  String? controlUrl(String serviceType) => services[serviceType];
}

/// 解析设备描述, 失败或缺少 UDN 时返回空.
DeviceDescription? parseDeviceDescription(
  String xml, {
  required String location,
}) {
  late final XmlDocument document;
  try {
    document = XmlDocument.parse(xml);
  } on XmlException {
    return null;
  }
  final base = Uri.tryParse(location);
  String textOf(XmlElement parent, String name, {String fallback = ''}) {
    for (final child in parent.childElements) {
      if (child.name.local == name) {
        return child.innerText.trim();
      }
    }
    return fallback;
  }

  XmlElement? device;
  for (final element in document.descendantElements) {
    if (element.name.local == 'device') {
      device = element;
      break;
    }
  }
  if (device == null) {
    return null;
  }
  final udn = textOf(device, 'UDN');
  if (udn.isEmpty) {
    return null;
  }
  final services = <String, String>{};
  for (final element in device.descendantElements) {
    if (element.name.local != 'service') {
      continue;
    }
    final type = textOf(element, 'serviceType');
    final control = textOf(element, 'controlURL');
    if (type.isEmpty || control.isEmpty) {
      continue;
    }
    final resolved = base == null ? control : base.resolve(control).toString();
    services[type] = resolved;
  }
  return DeviceDescription(
    udn: udn,
    name: textOf(device, 'friendlyName'),
    deviceType: textOf(device, 'deviceType'),
    manufacturer: textOf(device, 'manufacturer'),
    modelName: textOf(device, 'modelName'),
    services: services,
  );
}

String _escapeXml(String value) {
  return value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
}

/// 拼一个 SOAP 动作报文.
String soapRequest({
  required String service,
  required String action,
  Map<String, String> arguments = const {},
}) {
  final body = arguments.entries
      .map((entry) => '<${entry.key}>${_escapeXml(entry.value)}</${entry.key}>')
      .join();
  return '<?xml version="1.0" encoding="utf-8"?>'
      '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" '
      's:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">'
      '<s:Body><u:$action xmlns:u="$service">$body</u:$action></s:Body>'
      '</s:Envelope>';
}

/// 读取 SOAP 响应里的出参, 找不到动作时返回空表.
Map<String, String> parseSoapResponse(String xml, String action) {
  late final XmlDocument document;
  try {
    document = XmlDocument.parse(xml);
  } on XmlException {
    return const {};
  }
  for (final element in document.descendantElements) {
    if (element.name.local != '${action}Response') {
      continue;
    }
    return {
      for (final child in element.childElements)
        child.name.local: child.innerText.trim(),
    };
  }
  return const {};
}

/// UPnP 错误, 比如设备拒绝播放时返回 701.
class SoapFault implements Exception {
  const SoapFault(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() =>
      message.isEmpty ? 'UPnP 错误 $code' : '$message (UPnP $code)';
}

/// 从错误响应里取出 UPnP 错误码与描述, 不是错误报文时返回空.
SoapFault? parseSoapFault(String xml) {
  late final XmlDocument document;
  try {
    document = XmlDocument.parse(xml);
  } on XmlException {
    return null;
  }
  String? code;
  String? description;
  for (final element in document.descendantElements) {
    switch (element.name.local) {
      case 'errorCode':
        code = element.innerText.trim();
      case 'errorDescription':
        description = element.innerText.trim();
    }
  }
  if (code == null && description == null) {
    return null;
  }
  return SoapFault(code ?? '', description ?? '');
}

/// 按地址后缀猜媒体类型, 猜不到时按 mp4 处理.
String guessMimeType(String url) {
  final path = Uri.tryParse(url)?.path.toLowerCase() ?? '';
  if (path.endsWith('.m3u8')) {
    return 'application/vnd.apple.mpegurl';
  }
  if (path.endsWith('.flv')) {
    return 'video/x-flv';
  }
  if (path.endsWith('.mkv')) {
    return 'video/x-matroska';
  }
  if (path.endsWith('.webm')) {
    return 'video/webm';
  }
  if (path.endsWith('.mp3')) {
    return 'audio/mpeg';
  }
  return 'video/mp4';
}

/// 电视解析标题与封面的 DIDL-Lite 元数据.
String didlMetadata({
  required String title,
  required String url,
  String? mime,
}) {
  final type = mime ?? guessMimeType(url);
  return '<DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" '
      'xmlns:dc="http://purl.org/dc/elements/1.1/" '
      'xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/">'
      '<item id="0" parentID="-1" restricted="1">'
      '<dc:title>${_escapeXml(title)}</dc:title>'
      '<upnp:class>object.item.videoItem</upnp:class>'
      '<res protocolInfo="http-get:*:$type:$_protocolInfoSuffix">'
      '${_escapeXml(url)}</res>'
      '</item></DIDL-Lite>';
}

/// UPnP 的时间格式是 HH:MM:SS.
String formatUpnpDuration(Duration value) {
  final seconds = value.inSeconds.clamp(0, 359999);
  final hours = (seconds ~/ 3600).toString().padLeft(2, '0');
  final minutes = (seconds % 3600 ~/ 60).toString().padLeft(2, '0');
  final rest = (seconds % 60).toString().padLeft(2, '0');
  return '$hours:$minutes:$rest';
}

/// 解析 HH:MM:SS 或 MM:SS, 解析不出来时返回零.
Duration parseUpnpDuration(String value) {
  final parts = value.trim().split(':');
  final numbers = <int>[];
  for (final part in parts) {
    final number = int.tryParse(part.trim());
    if (number == null) {
      return Duration.zero;
    }
    numbers.add(number);
  }
  return switch (numbers.length) {
    3 => Duration(hours: numbers[0], minutes: numbers[1], seconds: numbers[2]),
    2 => Duration(minutes: numbers[0], seconds: numbers[1]),
    1 => Duration(seconds: numbers[0]),
    _ => Duration.zero,
  };
}
