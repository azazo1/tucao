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

  group('本地文件', () {
    late Directory directory;
    late File file;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('cast-proxy-');
      file = File('${directory.path}/movie.media');
      await file.writeAsBytes(_payload);
    });

    tearDown(() => directory.delete(recursive: true));

    Future<(HttpClientResponse, List<int>)> get(
      Uri uri, {
      String? range,
      String method = 'GET',
    }) async {
      final client = HttpClient();
      final request = await client.openUrl(method, uri);
      if (range != null) {
        request.headers.set(HttpHeaders.rangeHeader, range);
      }
      final response = await request.close();
      final bytes = await _readAll(response);
      client.close(force: true);
      return (response, bytes);
    }

    test('整段, 区间, 末尾区间与 HEAD 都按文件内容返回', () async {
      final uri = await proxy.registerFile(file, mime: 'video/mp4');

      final (whole, all) = await get(uri);
      expect(whole.statusCode, 200);
      expect(all, _payload);
      expect(whole.headers.value(HttpHeaders.acceptRangesHeader), 'bytes');

      final (part, middle) = await get(uri, range: 'bytes=100-199');
      expect(part.statusCode, 206);
      expect(middle, _payload.sublist(100, 200));
      expect(
        part.headers.value(HttpHeaders.contentRangeHeader),
        'bytes 100-199/4096',
      );

      final (_, open) = await get(uri, range: 'bytes=4000-');
      expect(open, _payload.sublist(4000));
      final (_, tail) = await get(uri, range: 'bytes=-96');
      expect(tail, _payload.sublist(4000));

      final (head, empty) = await get(uri, method: 'HEAD');
      expect(head.statusCode, 200);
      expect(head.contentLength, 4096);
      expect(empty, isEmpty);
    });

    test('区间越界返回 416, 文件不存在时拒绝登记', () async {
      final uri = await proxy.registerFile(file, mime: 'video/mp4');
      final (response, _) = await get(uri, range: 'bytes=5000-');
      expect(response.statusCode, 416);
      expect(
        response.headers.value(HttpHeaders.contentRangeHeader),
        'bytes */4096',
      );
      expect(
        () => proxy.registerFile(File('${directory.path}/missing.media')),
        throwsA(isA<CastException>()),
      );
    });

    test('按文件头判断媒体类型, 认不出时按 mp4', () async {
      await file.writeAsBytes([0x46, 0x4c, 0x56, 0x01, 0x05]);
      expect(await CastProxy.sniffMime(file), 'video/x-flv');
      await file.writeAsBytes([0x1a, 0x45, 0xdf, 0xa3, 0x01]);
      expect(await CastProxy.sniffMime(file), 'video/x-matroska');
      await file.writeAsBytes([0, 0, 0, 0x18, 0x66, 0x74, 0x79, 0x70]);
      expect(await CastProxy.sniffMime(file), 'video/mp4');
    });
  });

  test('非 http 地址拒绝登记', () async {
    expect(
      () => proxy.register('file:///sdcard/movie.mp4'),
      throwsA(isA<CastException>()),
    );
  });
}
