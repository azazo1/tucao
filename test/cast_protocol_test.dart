import 'package:flutter_test/flutter_test.dart';
import 'package:tucao/services/cast/upnp.dart';

const _descriptionXml = '''<?xml version="1.0" encoding="utf-8"?>
<root xmlns="urn:schemas-upnp-org:device-1-0">
  <specVersion><major>1</major><minor>0</minor></specVersion>
  <device>
    <deviceType>urn:schemas-upnp-org:device:MediaRenderer:1</deviceType>
    <friendlyName>客厅电视</friendlyName>
    <manufacturer>mock</manufacturer>
    <modelName>Mock TV</modelName>
    <UDN>uuid:abc</UDN>
    <serviceList>
      <service>
        <serviceType>urn:schemas-upnp-org:service:AVTransport:1</serviceType>
        <serviceId>urn:upnp-org:serviceId:AVTransport</serviceId>
        <controlURL>/control/AVTransport</controlURL>
      </service>
      <service>
        <serviceType>urn:schemas-upnp-org:service:RenderingControl:1</serviceType>
        <serviceId>urn:upnp-org:serviceId:RenderingControl</serviceId>
        <controlURL>/control/RenderingControl</controlURL>
      </service>
    </serviceList>
  </device>
</root>
''';

void main() {
  group('SSDP 报文', () {
    test('搜索报文带齐发现所需的头', () {
      final packet = buildMsearch();
      expect(packet, startsWith('M-SEARCH * HTTP/1.1\r\n'));
      expect(packet, contains('HOST: 239.255.255.250:1900\r\n'));
      expect(packet, contains('MAN: "ssdp:discover"\r\n'));
      expect(packet, contains('ST: $mediaRendererType\r\n'));
      expect(packet, endsWith('\r\n\r\n'));
    });

    test('解析单播响应', () {
      const text = 'HTTP/1.1 200 OK\r\n'
          'CACHE-CONTROL: max-age=1800\r\n'
          'LOCATION: http://192.168.1.10:9197/desc.xml\r\n'
          'ST: urn:schemas-upnp-org:device:MediaRenderer:1\r\n'
          'USN: uuid:abc::urn:schemas-upnp-org:device:MediaRenderer:1\r\n'
          '\r\n';
      final response = parseSsdpResponse(text);
      expect(response, isNotNull);
      expect(response!.location, 'http://192.168.1.10:9197/desc.xml');
      expect(response.usn, contains('uuid:abc'));
    });

    test('忽略广播与缺少地址的报文', () {
      expect(parseSsdpResponse('NOTIFY * HTTP/1.1\r\nLOCATION: x\r\n'), isNull);
      expect(parseSsdpResponse('HTTP/1.1 200 OK\r\nST: x\r\n'), isNull);
    });
  });

  group('设备描述', () {
    test('读出名称, UDN 与绝对控制地址', () {
      final description = parseDeviceDescription(
        _descriptionXml,
        location: 'http://192.168.1.10:1234/desc.xml',
      );
      expect(description, isNotNull);
      expect(description!.name, '客厅电视');
      expect(description.udn, 'uuid:abc');
      expect(description.isMediaRenderer, isTrue);
      expect(
        description.controlUrl(avTransportType),
        'http://192.168.1.10:1234/control/AVTransport',
      );
    });

    test('不是设备描述时返回空', () {
      expect(
        parseDeviceDescription('<html><body/></html>', location: 'http://x/'),
        isNull,
      );
    });
  });

  group('SOAP 报文', () {
    test('请求带命名空间与参数', () {
      final body = soapRequest(
        service: avTransportType,
        action: 'Play',
        arguments: const {'InstanceID': '0', 'Speed': '1'},
      );
      expect(body, contains('<u:Play xmlns:u="$avTransportType">'));
      expect(body, contains('<InstanceID>0</InstanceID>'));
      expect(body, contains('<Speed>1</Speed>'));
    });

    test('参数里的 XML 会被转义', () {
      final body = soapRequest(
        service: avTransportType,
        action: 'SetAVTransportURI',
        arguments: const {'CurrentURIMetaData': '<a b="1"/>'},
      );
      expect(body, contains('&lt;a b="1"/&gt;'));
      expect(body, isNot(contains('><a b="1"/>')));
    });

    test('解析动作出参', () {
      const xml = '<?xml version="1.0"?>'
          '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">'
          '<s:Body><u:GetTransportInfoResponse '
          'xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">'
          '<CurrentTransportState>PLAYING</CurrentTransportState>'
          '<CurrentSpeed>1</CurrentSpeed>'
          '</u:GetTransportInfoResponse></s:Body></s:Envelope>';
      final values = parseSoapResponse(xml, 'GetTransportInfo');
      expect(values['CurrentTransportState'], 'PLAYING');
      expect(values['CurrentSpeed'], '1');
    });

    test('解析 UPnP 错误码', () {
      const xml = '<?xml version="1.0"?>'
          '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">'
          '<s:Body><s:Fault><detail>'
          '<UPnPError><errorCode>701</errorCode>'
          '<errorDescription>Transition not available</errorDescription>'
          '</UPnPError></detail></s:Fault></s:Body></s:Envelope>';
      final fault = parseSoapFault(xml);
      expect(fault, isNotNull);
      expect(fault!.code, '701');
      expect(fault.message, 'Transition not available');
      expect(parseSoapResponse(xml, 'Stop'), isEmpty);
    });
  });

  group('媒体元数据', () {
    test('标题里的特殊字符会被转义', () {
      final didl = didlMetadata(
        title: 'A & B <集>',
        url: 'http://192.168.1.2:8080/a.mp4?x=1&y=2',
      );
      expect(didl, contains('<dc:title>A &amp; B &lt;集&gt;</dc:title>'));
      expect(didl, contains('x=1&amp;y=2'));
      expect(didl, contains('http-get:*:video/mp4:'));
    });

    test('按后缀猜类型', () {
      expect(guessMimeType('http://a/b.m3u8'), 'application/vnd.apple.mpegurl');
      expect(guessMimeType('http://a/b.flv'), 'video/x-flv');
      expect(guessMimeType('http://a/b.mp4'), 'video/mp4');
      expect(guessMimeType('http://a/b'), 'video/mp4');
    });
  });

  group('UPnP 时间', () {
    test('格式化与解析可以往返', () {
      const value = Duration(hours: 1, minutes: 2, seconds: 3);
      expect(formatUpnpDuration(value), '01:02:03');
      expect(parseUpnpDuration('01:02:03'), value);
    });

    test('解析异常输入返回零', () {
      expect(parseUpnpDuration(''), Duration.zero);
      expect(parseUpnpDuration('aa:bb'), Duration.zero);
      expect(parseUpnpDuration('05'), const Duration(seconds: 5));
    });
  });
}
