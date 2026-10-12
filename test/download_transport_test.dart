import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:tucao/common/constants.dart';
import 'package:tucao/services/download/download_transport.dart';

/// 全部响应由内存构造, 测试不会访问真实站点.
class _Adapter implements HttpClientAdapter {
  late FutureOr<ResponseBody> Function(RequestOptions options) respond;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return respond(options);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  final uri = Uri.parse('https://media.invalid/movie.mp4');
  late String workspace;
  late Directory tempRoot;
  late Directory directory;
  late File target;
  late _Adapter adapter;
  late Dio dio;
  late DioDownloadTransport transport;

  Future<int> fetch({
    Uri? source,
    CancelToken? cancelToken,
    void Function(int, int)? progress,
  }) => transport.fetch(
    uri: source ?? uri,
    target: target,
    cancelToken: cancelToken ?? CancelToken(),
    onProgress: progress ?? (_, _) {},
  );

  ResponseBody bytes(
    List<int> data, {
    String? mime = 'video/mp4',
    int? length,
    int status = 200,
  }) => ResponseBody.fromBytes(
    data,
    status,
    headers: {
      if (mime != null) Headers.contentTypeHeader: [mime],
      if (length != null) Headers.contentLengthHeader: ['$length'],
    },
  );

  setUp(() async {
    workspace = Directory.current.resolveSymbolicLinksSync();
    tempRoot = Directory(p.join(workspace, '.tmp'));
    await tempRoot.create(recursive: true);
    // 不接受指向工作区之外的 .tmp 符号链接.
    if (!p.equals(
      tempRoot.resolveSymbolicLinksSync(),
      tempRoot.absolute.path,
    )) {
      throw StateError('测试临时目录必须位于工作区 .tmp 内');
    }
    directory = await tempRoot.createTemp('download_transport_');
    target = File(p.join(directory.path, 'movie.mp4.part'));
    adapter = _Adapter();
    dio = Dio()..httpClientAdapter = adapter;
    transport = DioDownloadTransport(dio);
  });

  tearDown(() async {
    dio.close(force: true);
    // 删除前核对真实绝对路径, 只删除本测试在工作区 .tmp 中创建的目录.
    final absolute = directory.resolveSymbolicLinksSync();
    final allowedRoot = p.join(workspace, '.tmp');
    if (!p.isAbsolute(absolute) ||
        !p.isWithin(allowedRoot, absolute) ||
        !p.equals(absolute, directory.absolute.path)) {
      throw StateError('拒绝删除工作区 .tmp 之外的目录');
    }
    await Directory(absolute).delete(recursive: true);
  });

  test('流式写入返回实际字节数, 每块写完才回报进度, 复用请求拦截器', () async {
    final chunks = [
      Uint8List.fromList([0, 1, 2]),
      Uint8List.fromList([3, 4]),
    ];
    adapter.respond = (_) => ResponseBody(
      Stream.fromIterable(chunks),
      200,
      headers: {
        Headers.contentTypeHeader: ['video/mp4'],
        Headers.contentLengthHeader: ['5'],
      },
    );
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          options.headers['x-common-interceptor'] = 'used';
          handler.next(options);
        },
      ),
    );
    final progress = <List<int>>[];
    final received = await fetch(
      progress: (received, total) {
        expect(target.lengthSync(), received);
        progress.add([received, total]);
      },
    );
    expect(received, 5);
    expect(await target.readAsBytes(), [0, 1, 2, 3, 4]);
    expect(progress, [
      [3, 5],
      [5, 5],
    ]);
    final request = adapter.requests.single;
    expect(request.method, 'GET');
    expect(request.responseType, ResponseType.stream);
    expect(request.headers['user-agent'], Constants.userAgent);
    expect(request.headers['referer'], Constants.baseUrl);
    expect(request.headers['x-common-interceptor'], 'used');
    expect(
      request.headers.keys.any((key) => key.toLowerCase() == 'range'),
      isFalse,
    );
  });

  test('支持音频, 二进制与缺省 MIME, 未知长度为 -1', () async {
    for (final mime in ['audio/mpeg', 'application/octet-stream', null]) {
      adapter.respond = (_) => bytes([0, 2, 4], mime: mime);
      final progress = <List<int>>[];
      expect(await fetch(progress: (r, t) => progress.add([r, t])), 3);
      expect(progress, [
        [3, -1],
      ]);
    }
  });

  test('m3u8 路径直接拒绝且不发出网络请求', () async {
    await expectLater(
      fetch(source: Uri.parse('https://media.invalid/LIVE.M3U8?token=1')),
      throwsFormatException,
    );
    expect(adapter.requests, isEmpty);
    expect(target.existsSync(), isFalse);
  });

  test('拒绝非 200 状态与 HTML JSON 播放列表及其他非媒体 MIME', () async {
    for (final status in [204, 206, 404, 500]) {
      adapter.respond = (_) => bytes([1], status: status);
      await expectLater(fetch(), throwsFormatException);
      expect(target.existsSync(), isFalse);
    }
    for (final mime in [
      'text/html; charset=utf-8',
      'application/json',
      'application/problem+json',
      'application/vnd.apple.mpegurl',
      'audio/x-mpegurl',
      'text/plain',
    ]) {
      adapter.respond = (_) => bytes([1], mime: mime);
      await expectLater(fetch(), throwsFormatException);
      expect(target.existsSync(), isFalse);
    }
  });

  test('即使媒体 MIME 伪装也拒绝 HLS HTML 和 PHP 文本', () async {
    for (final text in [
      '\uFEFF \n#EXTM3U\n#EXTINF:4,\nsegment.ts',
      '<!DOCTYPE html><html>错误</html>',
      ' \n<HTML><body>错误</body></HTML>',
      '<?php echo "error";',
      '<br />\n<b>Warning</b>: failed to open stream',
      'PHP Fatal error: Uncaught Error',
      '{"error":"not media"}',
      '[{"error":"not media"}]',
    ]) {
      adapter.respond = (_) => bytes(utf8.encode(text));
      await expectLater(fetch(), throwsFormatException);
      expect(target.lengthSync(), 0);
    }
  });

  test('拆成小块的播放列表前缀仍被拒绝', () async {
    adapter.respond = (_) => ResponseBody(
      Stream.fromIterable([
        Uint8List.fromList(utf8.encode('#EX')),
        Uint8List.fromList(utf8.encode('TM3U\nsegment.ts')),
      ]),
      200,
    );
    await expectLater(fetch(), throwsFormatException);
    expect(await target.readAsString(), '#EX');
  });

  test('空文件与已知长度的短缺或超出均失败, 不删除部分文件', () async {
    for (final data in [
      <int>[],
      [1, 2],
      [1, 2, 3, 4],
    ]) {
      adapter.respond = (_) => bytes(data, length: 3);
      await expectLater(fetch(), throwsFormatException);
      expect(target.existsSync(), isTrue);
      expect(await target.readAsBytes(), data);
    }
    adapter.respond = (_) => bytes([]);
    await expectLater(fetch(), throwsFormatException);
  });

  test('传输前取消不发出请求, 分块写入后取消保留 Dio 取消异常', () async {
    final cancelled = CancelToken()..cancel('before request');
    await expectLater(
      fetch(cancelToken: cancelled),
      throwsA(
        isA<DioException>().having(
          (e) => e.type,
          'type',
          DioExceptionType.cancel,
        ),
      ),
    );
    expect(adapter.requests, isEmpty);
    final token = CancelToken();
    adapter.respond = (_) => ResponseBody(
      Stream.fromIterable([
        Uint8List.fromList([1, 2]),
        Uint8List.fromList([3, 4]),
      ]),
      200,
    );
    await expectLater(
      fetch(
        cancelToken: token,
        progress: (_, _) => token.cancel('after write'),
      ),
      throwsA(
        predicate<DioException>((error) => identical(error, token.cancelError)),
      ),
    );
    expect(await target.readAsBytes(), [1, 2]);
    // 失败后文件句柄已关闭, 父服务可以继续管理部分文件.
    final handle = await target.open(mode: FileMode.append);
    await handle.close();
  });

  test('Dio 网络异常保持原始对象, 不转为格式拒绝', () async {
    final error = DioException(
      requestOptions: RequestOptions(path: uri.toString()),
      type: DioExceptionType.connectionError,
      error: const SocketException('offline fake'),
    );
    adapter.respond = (_) => throw error;
    await expectLater(fetch(), throwsA(same(error)));
    expect(target.existsSync(), isFalse);
  });

  test('父服务未准备目录时不自动创建目录', () async {
    target = File(p.join(directory.path, 'unprepared', 'movie.part'));
    adapter.respond = (_) => bytes([1, 2]);
    await expectLater(fetch(), throwsA(isA<FileSystemException>()));
    expect(target.parent.existsSync(), isFalse);
  });
}
