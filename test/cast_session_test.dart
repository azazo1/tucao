import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tucao/models/cast_device.dart';
import 'package:tucao/services/cast/proxy.dart';
import 'package:tucao/services/cast/renderer.dart';
import 'package:tucao/services/cast/session.dart';
import 'package:tucao/services/cast/upnp.dart';

const _descriptionXml = '''<?xml version="1.0" encoding="utf-8"?>
<root xmlns="urn:schemas-upnp-org:device-1-0">
  <device>
    <deviceType>urn:schemas-upnp-org:device:MediaRenderer:1</deviceType>
    <friendlyName>测试电视</friendlyName>
    <UDN>uuid:session</UDN>
    <serviceList>
      <service>
        <serviceType>urn:schemas-upnp-org:service:AVTransport:1</serviceType>
        <serviceId>urn:upnp-org:serviceId:AVTransport</serviceId>
        <controlURL>/control/AVTransport</controlURL>
      </service>
    </serviceList>
  </device>
</root>
''';

String _envelope(String action, Map<String, String> values) {
  final body = values.entries
      .map((entry) => '<${entry.key}>${entry.value}</${entry.key}>')
      .join();
  return '<?xml version="1.0"?>'
      '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">'
      '<s:Body><u:${action}Response xmlns:u="$avTransportType">'
      '$body</u:${action}Response></s:Body></s:Envelope>';
}

/// 一台假电视: 记录收到的动作, 维护一个可以手动摆布的传输状态与位置.
class _FakeTv {
  _FakeTv(this.server) {
    server.listen((request) async {
      final response = request.response;
      if (request.uri.path == '/desc.xml') {
        response.headers.contentType = ContentType('text', 'xml', charset: 'utf-8');
        response.write(_descriptionXml);
        await response.close();
        return;
      }
      final header = request.headers.value('SOAPACTION') ?? '';
      final action = header.split('#').last.replaceAll('"', '');
      final body = await utf8.decoder.bind(request).join();
      actions.add(action);
      if (action == 'SetAVTransportURI') {
        lastUri = RegExp(r'<CurrentURI>(.*?)</CurrentURI>').firstMatch(body)?.group(1) ?? '';
        state = 'STOPPED';
      } else if (action == 'Play') {
        state = 'PLAYING';
      } else if (action == 'Pause') {
        state = 'PAUSED_PLAYBACK';
      } else if (action == 'Stop') {
        state = 'STOPPED';
        positionSeconds = 0;
      } else if (action == 'Seek') {
        if (rejectSeeks > 0) {
          rejectSeeks--;
          response.statusCode = HttpStatus.internalServerError;
          response.write(
            '<?xml version="1.0"?><s:Envelope '
            'xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body>'
            '<s:Fault><detail><UPnPError><errorCode>701</errorCode>'
            '<errorDescription>Transition not available</errorDescription>'
            '</UPnPError></detail></s:Fault></s:Body></s:Envelope>',
          );
          await response.close();
          return;
        }
        final target = RegExp(r'<Target>(.*?)</Target>').firstMatch(body)?.group(1) ?? '0';
        positionSeconds = _seconds(target);
      }
      response.headers.contentType = ContentType('text', 'xml', charset: 'utf-8');
      response.write(switch (action) {
        'GetTransportInfo' => _envelope(action, {'CurrentTransportState': state}),
        'GetPositionInfo' => _envelope(action, {
          'RelTime': _stamp(positionSeconds),
          'TrackDuration': '01:00:00',
        }),
        _ => _envelope(action, const {}),
      });
      await response.close();
    });
  }

  final HttpServer server;
  final List<String> actions = [];
  String lastUri = '';
  String state = 'STOPPED';
  int positionSeconds = 0;

  /// 前多少次 Seek 会被拒绝, 用来验证重开播放的回退.
  int rejectSeeks = 0;

  int port() => server.port;

  static int _seconds(String stamp) {
    final parts = stamp.split(':').map((part) => int.tryParse(part) ?? 0).toList();
    return parts.length == 3 ? parts[0] * 3600 + parts[1] * 60 + parts[2] : 0;
  }

  static String _stamp(int seconds) {
    final hours = (seconds ~/ 3600).toString().padLeft(2, '0');
    final minutes = (seconds % 3600 ~/ 60).toString().padLeft(2, '0');
    final rest = (seconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$rest';
  }
}

Future<void> _pump([int milliseconds = 300]) {
  return Future<void>.delayed(Duration(milliseconds: milliseconds));
}

void main() {
  late HttpServer tvServer;
  late HttpServer mediaServer;
  late _FakeTv tv;
  late CastSession session;

  setUp(() async {
    tvServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    tv = _FakeTv(tvServer);
    mediaServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    mediaServer.listen((request) async {
      request.response.headers.contentType = ContentType('video', 'mp4');
      request.response.write('media');
      await request.response.close();
    });
    final device = CastDevice(
      udn: 'uuid:session',
      name: '测试电视',
      location: 'http://127.0.0.1:${tv.port()}/desc.xml',
    );
    session = CastSession(
      device: device,
      renderer: DlnaRenderer(device: device),
      proxy: CastProxy(addressResolver: () async => '127.0.0.1'),
      pollInterval: const Duration(milliseconds: 100),
      seekGuard: const Duration(milliseconds: 800),
    );
  });

  tearDown(() async {
    session.dispose();
    await tvServer.close(force: true);
    await mediaServer.close(force: true);
  });

  String mediaUrl() => 'http://127.0.0.1:${mediaServer.port}/movie.mp4';

  test('开始投屏时下发转发地址并从本地进度接着放', () async {
    await session.start(
      mediaUrl: mediaUrl(),
      title: '第一集',
      startAt: const Duration(seconds: 30),
    );
    expect(session.state, CastState.playing);
    expect(session.position, const Duration(seconds: 30));
    expect(tv.actions, containsAllInOrder(['SetAVTransportURI', 'Play', 'Seek']));
    expect(tv.lastUri, startsWith('http://127.0.0.1:${session.proxy.port}/cast/'));
    expect(tv.lastUri, isNot(mediaUrl()));
  });

  test('手机上跳转会下发到电视并立刻更新位置', () async {
    await session.start(mediaUrl: mediaUrl(), title: '第一集');
    await session.seek(const Duration(minutes: 2));
    expect(tv.actions.last, 'Seek');
    expect(session.position, const Duration(minutes: 2));
  });

  test('电视拒绝 Seek 时重开播放', () async {
    tv.rejectSeeks = 1;
    await session.start(mediaUrl: mediaUrl(), title: '第一集');
    await session.seek(const Duration(minutes: 2));
    expect(
      tv.actions,
      containsAllInOrder(['Seek', 'Stop', 'SetAVTransportURI', 'Play', 'Seek']),
    );
    expect(session.state, CastState.playing);
    expect(session.position, const Duration(minutes: 2));
  });

  test('轮询把电视端位置同步回会话', () async {
    await session.start(mediaUrl: mediaUrl(), title: '第一集');
    tv.positionSeconds = 100;
    await _pump();
    expect(session.position, const Duration(seconds: 100));
  });

  test('跳转后短时间内不拿轮询位置覆盖界面', () async {
    await session.start(mediaUrl: mediaUrl(), title: '第一集');
    await session.seek(const Duration(minutes: 5));
    tv.positionSeconds = 10;
    await _pump(300);
    expect(session.position, const Duration(minutes: 5));
    await _pump(700);
    expect(session.position, const Duration(seconds: 10));
  });

  test('电视端被遥控器停下时会话结束', () async {
    await session.start(mediaUrl: mediaUrl(), title: '第一集');
    tv.state = 'STOPPED';
    await _pump();
    expect(session.state, CastState.finished);
  });
}
