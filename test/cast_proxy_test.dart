import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tucao/services/cast/cast_exception.dart';
import 'package:tucao/services/cast/proxy.dart';

/// 播放进度 4KB 的测试数据, 内容按字节区分, 便于核对 Range.
final _payload = List<int>.generate(4096, (index) => index % 251);

Future<List<int>> _readAll(HttpClientResponse response) {
  return response.fold<List<int>>([], (all, chunk) => all..addAll(chunk));
}

void main() {
  late HttpServer mediaServer;
  late CastProxy proxy;

  setUp(() async {
    // 模拟站点: 没有 Referer 就拒绝, 支持一段 Range.
    mediaServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    mediaServer.listen((request) async {
      final response = request.response;
      if (request.headers.value(HttpHeaders.refererHeader) == null) {
        response.statusCode = HttpStatus.forbidden;
        await response.close();
        return;
      }
      if (request.headers.value(HttpHeaders.rangeHeader) == 'bytes=100-199') {
        response.statusCode = HttpStatus.partialContent;
        response.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes 100-199/${_payload.length}',
        );
        response.add(_payload.sublist(100, 200));
      } else {
        response.headers.contentType = ContentType('video', 'mp4');
        response.add(_payload);
      }
      await response.close();
    });
    proxy = CastProxy(addressResolver: () async => '127.0.0.1');
  });

  tearDown(() async {
    proxy.dispose();
    await mediaServer.close(force: true);
  });

  test('补上 Referer 后能取到完整内容', () async {
    final uri = await proxy.register(
      'http://127.0.0.1:${mediaServer.port}/movie.mp4',
    );
    expect(uri.scheme, 'http');
    expect(uri.host, '127.0.0.1');
    expect(uri.port, proxy.port);

    final client = HttpClient();
    final request = await client.getUrl(uri);
    final response = await request.close();
    final bytes = await _readAll(response);
    client.close(force: true);

    expect(response.statusCode, 200);
    expect(bytes, _payload);
  });

  test('Range 请求原样透传', () async {
    final uri = await proxy.register(
      'http://127.0.0.1:${mediaServer.port}/movie.mp4',
    );
    final client = HttpClient();
    final request = await client.getUrl(uri);
    request.headers.set(HttpHeaders.rangeHeader, 'bytes=100-199');
    final response = await request.close();
    final bytes = await _readAll(response);
    client.close(force: true);

    expect(response.statusCode, 206);
    expect(bytes, _payload.sublist(100, 200));
    expect(
      response.headers.value(HttpHeaders.contentRangeHeader),
      'bytes 100-199/4096',
    );
  });

  test('未登记的地址返回 404', () async {
    await proxy.register('http://127.0.0.1:${mediaServer.port}/movie.mp4');
    final client = HttpClient();
    final request = await client.getUrl(
      Uri.parse('http://127.0.0.1:${proxy.port}/cast/nothing'),
    );
    final response = await request.close();
    await response.drain<void>();
    client.close(force: true);
    expect(response.statusCode, 404);
  });

  test('非 http 地址拒绝登记', () async {
    expect(
      () => proxy.register('file:///sdcard/movie.mp4'),
      throwsA(isA<CastException>()),
    );
  });
}
