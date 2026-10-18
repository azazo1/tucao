import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:tucao/models/cast_device.dart';
import 'package:tucao/services/cast/cast_exception.dart';
import 'package:tucao/services/cast/upnp.dart';

/// 电视当前的播放状态.
class CastPlayback {
  const CastPlayback({
    required this.state,
    required this.position,
    required this.duration,
  });

  /// UPnP 原始状态, 例如 PLAYING / PAUSED_PLAYBACK / STOPPED.
  final String state;
  final Duration position;
  final Duration duration;

  bool get playing => state == 'PLAYING';

  bool get paused => state == 'PAUSED_PLAYBACK';

  bool get stopped => state == 'STOPPED' || state == 'NO_MEDIA_PRESENT';
}

/// 一台 DLNA 渲染设备的控制客户端.
///
/// 只做 AVTransport 这几个动作, 足够完成投屏, 暂停, 继续, 跳转与退出;
/// 音量等能力各品牌差异大, 暂不接入.
class DlnaRenderer {
  DlnaRenderer({
    required this.device,
    HttpClient? client,
    this.userAgent = 'Linux/3.14.0 UPnP/1.1 tucao/1.0 DLNADOC/1.50',
    this.timeout = const Duration(seconds: 6),
  }) : _client = client ?? HttpClient() {
    _client.connectionTimeout = timeout;
    _client.autoUncompress = false;
  }

  final CastDevice device;

  final String userAgent;

  final Duration timeout;

  final HttpClient _client;

  DeviceDescription? _description;

  /// 读取并缓存设备描述, 控制地址按它解析.
  Future<DeviceDescription> describe() async {
    final cached = _description;
    if (cached != null) {
      return cached;
    }
    final uri = Uri.tryParse(device.location);
    if (uri == null) {
      throw const CastException('设备地址无效');
    }
    final String body;
    try {
      final request = await _client.getUrl(uri);
      request.headers.set(HttpHeaders.userAgentHeader, userAgent);
      request.headers.set(HttpHeaders.connectionHeader, 'close');
      final response = await request.close().timeout(timeout);
      body = await response.transform(utf8.decoder).join();
      if (response.statusCode != HttpStatus.ok) {
        throw CastException('读取设备描述失败 HTTP ${response.statusCode}');
      }
    } on SocketException catch (error) {
      throw CastException('连接设备失败: ${error.message}');
    } on TimeoutException {
      throw const CastException('连接设备超时');
    }
    final description = parseDeviceDescription(body, location: device.location);
    if (description == null) {
      throw const CastException('设备描述无法解析');
    }
    _description = description;
    return description;
  }

  Future<String> _controlUrl(String serviceType) async {
    final description = await describe();
    final url = description.controlUrl(serviceType);
    if (url == null) {
      throw const CastException('该设备不支持投屏控制');
    }
    return url;
  }

  Future<Map<String, String>> _invoke(
    String serviceType,
    String action,
    Map<String, String> arguments,
  ) async {
    final controlUrl = await _controlUrl(serviceType);
    final payload = utf8.encode(
      soapRequest(service: serviceType, action: action, arguments: arguments),
    );
    final String body;
    final int status;
    try {
      final request = await _client.postUrl(Uri.parse(controlUrl));
      request.headers.set(
        HttpHeaders.contentTypeHeader,
        'text/xml; charset="utf-8"',
      );
      request.headers.set('SOAPACTION', '"$serviceType#$action"');
      request.headers.set(HttpHeaders.userAgentHeader, userAgent);
      request.headers.set(HttpHeaders.connectionHeader, 'close');
      request.contentLength = payload.length;
      request.add(payload);
      final response = await request.close().timeout(timeout);
      status = response.statusCode;
      body = await response.transform(utf8.decoder).join();
    } on SocketException catch (error) {
      throw CastException('连接设备失败: ${error.message}');
    } on TimeoutException {
      throw const CastException('设备响应超时');
    }
    if (status != HttpStatus.ok) {
      final fault = parseSoapFault(body);
      if (fault != null) {
        throw fault;
      }
      throw CastException('设备返回 HTTP $status');
    }
    return parseSoapResponse(body, action);
  }

  /// 把媒体地址交给电视, 并附带标题等元数据.
  Future<void> setMedia(String url, {required String title, String? mime}) async {
    await _invoke(avTransportType, 'SetAVTransportURI', {
      'InstanceID': '0',
      'CurrentURI': url,
      'CurrentURIMetaData': didlMetadata(title: title, url: url, mime: mime),
    });
  }

  Future<void> play() async {
    await _invoke(avTransportType, 'Play', {
      'InstanceID': '0',
      'Speed': '1',
    });
  }

  Future<void> pause() async {
    await _invoke(avTransportType, 'Pause', {'InstanceID': '0'});
  }

  Future<void> stop() async {
    await _invoke(avTransportType, 'Stop', {'InstanceID': '0'});
  }

  Future<void> seek(Duration position) async {
    await _invoke(avTransportType, 'Seek', {
      'InstanceID': '0',
      'Unit': 'REL_TIME',
      'Target': formatUpnpDuration(position),
    });
  }

  /// 读取电视端的进度与状态, 界面按它同步.
  Future<CastPlayback> fetchPlayback() async {
    final info = await _invoke(avTransportType, 'GetTransportInfo', {
      'InstanceID': '0',
    });
    final position = await _invoke(avTransportType, 'GetPositionInfo', {
      'InstanceID': '0',
    });
    return CastPlayback(
      state: info['CurrentTransportState'] ?? 'UNKNOWN',
      position: parseUpnpDuration(position['RelTime'] ?? ''),
      duration: parseUpnpDuration(position['TrackDuration'] ?? ''),
    );
  }

  void dispose() {
    _client.close(force: true);
  }
}
