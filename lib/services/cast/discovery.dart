import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:tucao/common/constants.dart';
import 'package:tucao/models/cast_device.dart';
import 'package:tucao/services/cast/upnp.dart';
import 'package:tucao/utils/logger.dart';

/// 在局域网里搜索可投屏设备.
///
/// 只依赖 M-SEARCH 的单播响应: 组播接收在安卓上需要额外的 MulticastLock,
/// 而绝大多数电视与盒子都会按 MX 直接回给搜索方, 这样实现更省事.
class CastDiscovery {
  CastDiscovery({
    this.timeout = const Duration(seconds: 4),
    this.userAgent = Constants.userAgent,
    HttpClient? client,
  }) : _client =
           client ??
           (HttpClient()..connectionTimeout = const Duration(seconds: 3));

  /// 收响应的总时长.
  final Duration timeout;

  final String userAgent;

  final HttpClient _client;

  /// 搜一轮, 完成设备描述解析后按名字排序返回.
  Future<List<CastDevice>> search() async {
    final responses = await _search();
    final devices = <String, CastDevice>{};
    await Future.wait(
      responses.map((response) async {
        final description = await _fetchDescription(response.location);
        if (description == null || !description.isMediaRenderer) {
          return;
        }
        devices[description.udn] = CastDevice(
          udn: description.udn,
          name: description.name.isEmpty ? response.location : description.name,
          location: response.location,
          manufacturer: description.manufacturer,
          modelName: description.modelName,
        );
      }),
    );
    final list = devices.values.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    Log.i('投屏搜索完成, 设备 ${list.length} 个');
    return list;
  }

  Future<List<SsdpResponse>> _search() async {
    final RawDatagramSocket socket;
    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    } on SocketException catch (error) {
      Log.w('投屏搜索无法建立套接字: $error');
      return const [];
    }
    final responses = <SsdpResponse>[];
    final seen = <String>{};
    final packet = utf8.encode(buildMsearch());
    final group = InternetAddress(ssdpGroup);
    final completer = Completer<void>();
    socket.multicastHops = 2;
    final subscription = socket.listen(
      (event) {
        if (event != RawSocketEvent.read) {
          return;
        }
        final datagram = socket.receive();
        if (datagram == null) {
          return;
        }
        final text = utf8.decode(datagram.data, allowMalformed: true);
        final response = parseSsdpResponse(text);
        if (response == null || !seen.add(response.location)) {
          return;
        }
        responses.add(response);
      },
      onError: (Object error) {
        Log.w('投屏搜索接收失败: $error');
        if (!completer.isCompleted) {
          completer.complete();
        }
      },
    );
    try {
      socket.send(packet, group, ssdpPort);
      // 有些设备对第一包不响应, 中途补发一次, 仍在 timeout 之内.
      final resend = Timer(timeout ~/ 2, () {
        try {
          socket.send(packet, group, ssdpPort);
        } on SocketException {
          // 设备已经关闭套接字时忽略, 由外层超时收尾.
        }
      });
      await completer.future.timeout(timeout, onTimeout: () {});
      resend.cancel();
    } finally {
      await subscription.cancel();
      socket.close();
    }
    return responses;
  }

  Future<DeviceDescription?> _fetchDescription(String location) async {
    try {
      final uri = Uri.tryParse(location);
      if (uri == null) {
        return null;
      }
      final request = await _client.getUrl(uri);
      request.headers.set(HttpHeaders.userAgentHeader, userAgent);
      request.headers.set(HttpHeaders.connectionHeader, 'close');
      final response = await request.close().timeout(
        const Duration(seconds: 4),
      );
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode != HttpStatus.ok) {
        return null;
      }
      return parseDeviceDescription(body, location: location);
    } catch (error) {
      Log.w('读取投屏设备描述失败 $location: $error');
      return null;
    }
  }

  void dispose() {
    _client.close(force: true);
  }
}
