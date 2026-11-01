import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:tucao/common/constants.dart';
import 'package:tucao/services/download/download_segments.dart';
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
    int offset = 0,
    int expectedTotal = -1,
  }) => transport.fetch(
    uri: source ?? uri,
    target: target,
    cancelToken: cancelToken ?? CancelToken(),
    onProgress: progress ?? (_, _) {},
    offset: offset,
    expectedTotal: expectedTotal,
  );

  ResponseBody bytes(
    List<int> data, {
    String? mime = 'video/mp4',
    int? length,
    int status = 200,
    String? range,
  }) => ResponseBody.fromBytes(
    data,
    status,
    headers: {
      if (mime != null) Headers.contentTypeHeader: [mime],
      if (length != null) Headers.contentLengthHeader: ['$length'],
      if (range != null) 'content-range': [range],
    },
  );

  bool ranged(RequestOptions options) =>
      options.headers.keys.any((key) => key.toLowerCase() == 'range');

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

  test('空文件与超出长度是无效内容, 提前断开可续传, 都不删除部分文件', () async {
    for (final (data, matcher) in [
      (<int>[], throwsFormatException),
      ([1, 2], throwsA(isA<DownloadInterruptedException>())),
      ([1, 2, 3, 4], throwsFormatException),
    ]) {
      adapter.respond = (_) => bytes(data, length: 3);
      await expectLater(fetch(), matcher);
      expect(target.existsSync(), isTrue);
      expect(await target.readAsBytes(), data);
    }
    adapter.respond = (_) => bytes([]);
    await expectLater(fetch(), throwsFormatException);
  });

  test('206 从分片末尾续传, 先截掉起点之后的残留', () async {
    await target.writeAsBytes([1, 2, 9]);
    adapter.respond = (_) =>
        bytes([3, 4, 5], status: 206, length: 3, range: 'bytes 2-4/5');
    final progress = <List<int>>[];
    final received = await fetch(
      offset: 2,
      expectedTotal: 5,
      progress: (received, total) => progress.add([received, total]),
    );
    expect(received, 5);
    expect(await target.readAsBytes(), [1, 2, 3, 4, 5]);
    expect(progress, [
      [5, 5],
    ]);
    expect(adapter.requests.single.headers['range'], 'bytes=2-');
  });

  test('服务端不支持续传时返回 200, 从头覆盖分片', () async {
    await target.writeAsBytes([1, 2]);
    adapter.respond = (_) => bytes([7, 8, 9], length: 3);
    expect(await fetch(offset: 2, expectedTotal: 3), 3);
    expect(await target.readAsBytes(), [7, 8, 9]);
    expect(adapter.requests.length, 1);
  });

  test('总长变化, 区间不符与 416 都丢弃分片重新请求整个文件', () async {
    for (final partial in [
      bytes([3, 4, 5], status: 206, length: 3, range: 'bytes 2-4/9'),
      bytes([3, 4, 5], status: 206, length: 3, range: 'bytes 0-2/5'),
      bytes([], status: 416, mime: null),
    ]) {
      adapter.requests.clear();
      await target.writeAsBytes([1, 2]);
      adapter.respond = (options) =>
          ranged(options) ? partial : bytes([6, 7, 8, 9, 10], length: 5);
      expect(await fetch(offset: 2, expectedTotal: 5), 5);
      expect(await target.readAsBytes(), [6, 7, 8, 9, 10]);
      expect(adapter.requests.map(ranged), [true, false]);
    }
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

  group('分段下载', () {
    final data = List.generate(12, (index) => index + 10);

    String? rangeOf(RequestOptions options) {
      for (final entry in options.headers.entries) {
        if (entry.key.toLowerCase() == 'range') {
          return entry.value as String;
        }
      }
      return null;
    }

    /// 按请求头的区间返回 [content], 没有区间时返回整包.
    ResponseBody serve(List<int> content, RequestOptions options) {
      final match = RegExp(
        r'^bytes=(\d+)-(\d*)$',
      ).firstMatch(rangeOf(options) ?? '');
      if (match == null) {
        return bytes(content, length: content.length);
      }
      final start = int.parse(match.group(1)!);
      final end = match.group(2)!.isEmpty
          ? content.length - 1
          : int.parse(match.group(2)!);
      final slice = content.sublist(start, end + 1);
      return bytes(
        slice,
        status: 206,
        length: slice.length,
        range: 'bytes $start-$end/${content.length}',
      );
    }

    List<String> files() =>
        directory.listSync().map((entry) => p.basename(entry.path)).toList();

    setUp(() => transport = DioDownloadTransport(dio, minSegmentSize: 4));

    test('探测支持区间后并发下载各段, 按顺序合并并清掉计划与各段', () async {
      adapter.respond = (options) => serve(data, options);
      final progress = <List<int>>[];
      final received = await transport.fetch(
        uri: uri,
        target: target,
        cancelToken: CancelToken(),
        connections: 3,
        onProgress: (r, t) => progress.add([r, t]),
      );
      expect(received, 12);
      expect(await target.readAsBytes(), data);
      final ranges = adapter.requests.map(rangeOf).toList();
      expect(ranges.first, 'bytes=0-0');
      expect(ranges.skip(1), unorderedEquals(['bytes=0-3', 'bytes=4-7', 'bytes=8-11']));
      expect(progress.last, [12, 12]);
      expect(files(), ['movie.mp4.part']);
    });

    test('某段中断后保留计划, 再次下载只补各段缺的部分', () async {
      adapter.respond = (options) {
        if (rangeOf(options) == 'bytes=4-7') {
          // 声明整段, 只给出两个字节就断开.
          return bytes(data.sublist(4, 6), status: 206, range: 'bytes 4-7/12');
        }
        return serve(data, options);
      };
      await expectLater(
        transport.fetch(
          uri: uri,
          target: target,
          cancelToken: CancelToken(),
          connections: 3,
          onProgress: (_, _) {},
        ),
        throwsA(isA<DownloadInterruptedException>()),
      );
      expect(files(), contains('movie.mp4.part.plan'));
      adapter.requests.clear();
      adapter.respond = (options) => serve(data, options);
      // 计划优先, 不看本次的连接数.
      final received = await transport.fetch(
        uri: uri,
        target: target,
        cancelToken: CancelToken(),
        onProgress: (_, _) {},
      );
      expect(received, 12);
      expect(await target.readAsBytes(), data);
      final ranges = adapter.requests.map(rangeOf).toList();
      expect(ranges, contains('bytes=6-7'));
      expect(ranges, isNot(contains('bytes=0-0')));
      expect(ranges, isNot(contains(null)));
      expect(files(), ['movie.mp4.part']);
    });

    test('服务端忽略区间时退回单连接, 不留下计划', () async {
      adapter.respond = (_) => bytes(data, length: data.length);
      final received = await transport.fetch(
        uri: uri,
        target: target,
        cancelToken: CancelToken(),
        connections: 3,
        onProgress: (_, _) {},
      );
      expect(received, 12);
      expect(await target.readAsBytes(), data);
      expect(adapter.requests.map(rangeOf), ['bytes=0-0', null]);
      expect(files(), ['movie.mp4.part']);
    });

    test('服务端文件大小与计划不符时丢掉各段, 从头下载', () async {
      await DownloadSegments.save(
        target,
        const SegmentPlan(
          total: 12,
          ranges: [(start: 0, end: 5), (start: 6, end: 11)],
        ),
      );
      await DownloadSegments.segment(target, 0).writeAsBytes([9, 9, 9]);
      await DownloadSegments.segment(target, 1).writeAsBytes([8]);
      final changed = List.generate(16, (index) => index);
      adapter.respond = (options) => serve(changed, options);
      final received = await transport.fetch(
        uri: uri,
        target: target,
        cancelToken: CancelToken(),
        onProgress: (_, _) {},
      );
      expect(received, 16);
      expect(await target.readAsBytes(), changed);
      expect(files(), ['movie.mp4.part']);
    });
  });

  test('父服务未准备目录时不自动创建目录', () async {
    target = File(p.join(directory.path, 'unprepared', 'movie.part'));
    adapter.respond = (_) => bytes([1, 2]);
    await expectLater(fetch(), throwsA(isA<FileSystemException>()));
    expect(target.parent.existsSync(), isFalse);
  });
}
