import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tucao/models/cast_device.dart';
import 'package:tucao/services/cast/renderer.dart';
import 'package:tucao/services/cast/upnp.dart';

String _envelope(String action, Map<String, String> values) {
  final body = values.entries
      .map((entry) => '<${entry.key}>${entry.value}</${entry.key}>')
      .join();
  return '<?xml version="1.0" encoding="utf-8"?>'
      '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">'
      '<s:Body><u:${action}Response '
      'xmlns:u="$avTransportType">$body</u:${action}Response>'
      '</s:Body></s:Envelope>';
}

const _descriptionXml = '''<?xml version="1.0" encoding="utf-8"?>
<root xmlns="urn:schemas-upnp-org:device-1-0">
  <device>
    <deviceType>urn:schemas-upnp-org:device:MediaRenderer:1</deviceType>
    <friendlyName>测试电视</friendlyName>
    <UDN>uuid:test</UDN>
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

void main() {
  late HttpServer server;
  late List<String> actions;
  late List<String> bodies;
  var failPlay = false;

  setUp(() async {
    actions = [];
    bodies = [];
    failPlay = false;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
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
      bodies.add(await utf8.decoder.bind(request).join());
      actions.add(action);
      if (failPlay && action == 'Play') {
        response.statusCode = HttpStatus.internalServerError;
        response.write(
          '<?xml version="1.0"?>'
          '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">'
          '<s:Body><s:Fault><detail><UPnPError>'
          '<errorCode>701</errorCode>'
          '<errorDescription>Transition not available</errorDescription>'
          '</UPnPError></detail></s:Fault></s:Body></s:Envelope>',
        );
        await response.close();
        return;
      }
      response.headers.contentType = ContentType('text', 'xml', charset: 'utf-8');
      response.write(switch (action) {
        'GetTransportInfo' => _envelope(action, {
          'CurrentTransportState': 'PLAYING',
          'CurrentTransportStatus': 'OK',
          'CurrentSpeed': '1',
        }),
        'GetPositionInfo' => _envelope(action, {
          'RelTime': '00:00:42',
          'TrackDuration': '01:00:00',
        }),
        _ => _envelope(action, const {}),
      });
      await response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
  });

  DlnaRenderer renderer() {
    return DlnaRenderer(
      device: CastDevice(
        udn: 'uuid:test',
        name: '测试电视',
        location: 'http://127.0.0.1:${server.port}/desc.xml',
      ),
    );
  }

  test('下发地址时带上标题元数据', () async {
    final sut = renderer();
    await sut.setMedia(
      'http://192.168.1.2:8080/cast/abc',
      title: '第 1 集',
      mime: 'video/mp4',
    );
    sut.dispose();
    expect(actions, ['SetAVTransportURI']);
    expect(bodies.single, contains('<CurrentURI>http://192.168.1.2:8080/cast/abc</CurrentURI>'));
    expect(bodies.single, contains('&lt;DIDL-Lite'));
    expect(bodies.single, contains('第 1 集'));
  });

  test('播放, 暂停, 停止依次下发', () async {
    final sut = renderer();
    await sut.play();
    await sut.pause();
    await sut.stop();
    sut.dispose();
    expect(actions, ['Play', 'Pause', 'Stop']);
  });

  test('跳转用 HH:MM:SS 目标', () async {
    final sut = renderer();
    await sut.seek(const Duration(minutes: 3, seconds: 7));
    sut.dispose();
    expect(actions, ['Seek']);
    expect(bodies.single, contains('<Target>00:03:07</Target>'));
    expect(bodies.single, contains('<Unit>REL_TIME</Unit>'));
  });

  test('读取电视端进度与状态', () async {
    final sut = renderer();
    final playback = await sut.fetchPlayback();
    sut.dispose();
    expect(playback.state, 'PLAYING');
    expect(playback.playing, isTrue);
    expect(playback.position, const Duration(seconds: 42));
    expect(playback.duration, const Duration(hours: 1));
  });

  test('设备拒绝播放时抛出 UPnP 错误', () async {
    failPlay = true;
    final sut = renderer();
    await expectLater(sut.play(), throwsA(isA<SoapFault>()));
    sut.dispose();
  });
}
