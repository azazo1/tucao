import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:tucao/common/constants.dart';
import 'package:tucao/services/download/download_segments.dart';
import 'package:tucao/utils/logger.dart';

/// 连接提前结束. 已写入的部分仍然有效, 下次可以续传.
class DownloadInterruptedException implements Exception {
  const DownloadInterruptedException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 单文件媒体传输, 文件目录与最终提交由下载服务负责.
abstract class DownloadTransport {
  /// 把 [uri] 写进 [target], 返回写完后的文件总字节数.
  ///
  /// [offset] 大于 0 时按 Range 从该字节续传, 追加到 [target] 末尾.
  /// 服务端不支持区间时退回从头下载并覆盖 [target].
  /// [expectedTotal] 是上次记下的总大小, 与服务端不一致说明文件已变, 从头下载.
  /// [onProgress] 的两个值都是整个文件的绝对字节数, 不是本次请求的增量.
  ///
  /// [connections] 大于 1 时, 从头开始的下载按 Range 分段并发, 各段与计划写在
  /// [target] 旁边 (见 [DownloadSegments]), 下完拼回 [target]. 已有分段计划时
  /// 按计划续传, 不看 [connections] 与 [offset].
  Future<int> fetch({
    required Uri uri,
    required File target,
    required CancelToken cancelToken,
    required void Function(int received, int total) onProgress,
    int offset = 0,
    int expectedTotal = -1,
    int connections = 1,
  });
}

/// 分段计划与服务端当前的文件对不上, 只能丢掉各段从头下载.
class _PlanInvalid implements Exception {
  const _PlanInvalid();
}

/// 使用公共 Dio 客户端的拦截器, 不创建目录或提交最终文件.
class DioDownloadTransport implements DownloadTransport {
  DioDownloadTransport(this._dio, {this.minSegmentSize = DownloadSegments.minSize});

  final Dio _dio;

  /// 每段的最小字节数, 测试里调小以免构造大文件.
  final int minSegmentSize;

  @override
  Future<int> fetch({
    required Uri uri,
    required File target,
    required CancelToken cancelToken,
    required void Function(int received, int total) onProgress,
    int offset = 0,
    int expectedTotal = -1,
    int connections = 1,
  }) async {
    var start = offset;
    final saved = await DownloadSegments.load(target);
    if (saved != null) {
      final bytes = await _fetchPlan(
        uri: uri,
        target: target,
        plan: saved,
        cancelToken: cancelToken,
        onProgress: onProgress,
      );
      if (bytes != null) {
        return bytes;
      }
      Log.w('分段续传条件不满足, 从头下载: $uri');
      await DownloadSegments.clear(target);
      start = 0;
    }
    if (start > 0) {
      final resumed = await _fetchOnce(
        uri: uri,
        target: target,
        cancelToken: cancelToken,
        onProgress: onProgress,
        offset: start,
        expectedTotal: expectedTotal,
      );
      if (resumed != null) {
        return resumed;
      }
      Log.w('续传条件不满足, 从头下载: $uri');
    }
    if (connections > 1) {
      final total = await _probe(uri, cancelToken);
      final ranges = total == null
          ? null
          : DownloadSegments.split(total, connections, minSize: minSegmentSize);
      if (total == null) {
        Log.w('服务端不支持分段下载, 改用单连接: ${uri.host}');
      } else if (ranges != null) {
        final plan = SegmentPlan(total: total, ranges: ranges);
        await DownloadSegments.save(target, plan);
        Log.i('分段下载 ${ranges.length} 段, 共 $total 字节: ${uri.host}');
        final bytes = await _fetchPlan(
          uri: uri,
          target: target,
          plan: plan,
          cancelToken: cancelToken,
          onProgress: onProgress,
        );
        if (bytes != null) {
          return bytes;
        }
        Log.w('分段下载途中服务端文件变化, 改用单连接: $uri');
        await DownloadSegments.clear(target);
      }
    }
    final bytes = await _fetchOnce(
      uri: uri,
      target: target,
      cancelToken: cancelToken,
      onProgress: onProgress,
      offset: 0,
      expectedTotal: -1,
    );
    // 从零开始的请求不会要求重新开始.
    return bytes!;
  }

  /// 发一次请求. 返回空表示本地分片不能接着用, 需要从头下载.
  Future<int?> _fetchOnce({
    required Uri uri,
    required File target,
    required CancelToken cancelToken,
    required void Function(int received, int total) onProgress,
    required int offset,
    required int expectedTotal,
  }) async {
    cancelToken.throwIfCancellationRequested();
    _rejectPlaylistPath(uri);
    final resume = offset > 0;
    final response = await _dio.getUri<ResponseBody>(
      uri,
      cancelToken: cancelToken,
      options: Options(
        responseType: ResponseType.stream,
        headers: _headers(range: resume ? 'bytes=$offset-' : null),
        // 状态码由传输层检查, 网络错误仍由 Dio 原样上抛.
        validateStatus: (_) => true,
      ),
    );
    final body = response.data;
    if (body == null) {
      throw const FormatException('下载响应为空');
    }
    RandomAccessFile? output;
    var streamStarted = false;
    try {
      cancelToken.throwIfCancellationRequested();
      final status = response.statusCode;
      final lengthHeader = response.headers.value(Headers.contentLengthHeader);
      final length = lengthHeader == null ? -1 : int.tryParse(lengthHeader);
      if (length == null || (lengthHeader != null && length < 0)) {
        throw const FormatException('下载响应的 Content-Length 无效');
      }
      var start = 0;
      int total;
      if (resume && status == 206) {
        final range = _parseContentRange(
          response.headers.value('content-range'),
        );
        if (range == null || range.start != offset) {
          Log.w('续传响应区间与本地分片不符: ${response.headers.value('content-range')}');
          return null;
        }
        total = range.total >= 0
            ? range.total
            : (length >= 0 ? offset + length : -1);
        if (expectedTotal >= 0 && total >= 0 && total != expectedTotal) {
          // 服务端文件大小变了, 旧分片不能和新内容拼接.
          return null;
        }
        start = offset;
      } else if (resume && status == 416) {
        // 本地分片已超出服务端文件, 只能从头来.
        return null;
      } else if (status == 200) {
        total = length;
      } else {
        throw FormatException('下载失败, 收到状态码 $status');
      }
      _rejectPlaylistPath(response.realUri);
      _validateMime(response.headers.value(Headers.contentTypeHeader));
      if (start > 0) {
        // 先截到续传起点, 避免分片末尾残留半个块.
        output = await target.open(mode: FileMode.append);
        await output.truncate(start);
        await output.setPosition(start);
      } else {
        output = await target.open(mode: FileMode.write);
      }
      var received = start;
      final prefix = <int>[];
      streamStarted = true;
      await for (final chunk in body.stream) {
        cancelToken.throwIfCancellationRequested();
        if (chunk.isEmpty) continue;
        // 只检查文件开头, 续传的中段本来就是二进制, 不需要再嗅探.
        if (start == 0 && prefix.length < 512) {
          prefix.addAll(chunk.take(512 - prefix.length));
          _sniff(prefix);
        }
        await output.writeFrom(chunk);
        received += chunk.length;
        onProgress(received, total);
        cancelToken.throwIfCancellationRequested();
        if (total >= 0 && received > total) {
          throw const FormatException('下载字节数超过 Content-Length');
        }
      }
      cancelToken.throwIfCancellationRequested();
      if (received == 0) {
        throw const FormatException('下载文件为空');
      }
      if (total >= 0 && received != total) {
        throw DownloadInterruptedException(
          '下载中断, 预期 $total 字节, 实际 $received 字节',
        );
      }
      return received;
    } finally {
      // 拒绝响应或打开文件失败时, 也取消尚未消费的响应流.
      try {
        if (!streamStarted) {
          await body.stream.listen((_) {}).cancel();
        }
      } finally {
        await output?.close();
      }
    }
  }

  static Map<String, String> _headers({String? range}) => {
    'user-agent': Constants.userAgent,
    'referer': Constants.baseUrl,
    if (range != null) 'range': range,
  };

  /// 请求首字节, 服务端按区间返回且给出总长时返回总长, 否则为空.
  ///
  /// 返回 200 说明忽略了 Range, 其余状态码交给随后的单连接请求报错.
  Future<int?> _probe(Uri uri, CancelToken cancelToken) async {
    cancelToken.throwIfCancellationRequested();
    _rejectPlaylistPath(uri);
    final response = await _dio.getUri<ResponseBody>(
      uri,
      cancelToken: cancelToken,
      options: Options(
        responseType: ResponseType.stream,
        headers: _headers(range: 'bytes=0-0'),
        validateStatus: (_) => true,
      ),
    );
    // 只要响应头, 200 时也不读整包.
    await response.data?.stream.listen((_) {}).cancel();
    if (response.statusCode != 206) {
      return null;
    }
    final range = _parseContentRange(response.headers.value('content-range'));
    if (range == null || range.start != 0 || range.total <= 0) {
      return null;
    }
    return range.total;
  }

  /// 按计划并发下载各段并拼回 [target]. 计划已失效时返回空.
  ///
  /// 一段失败就停掉其余各段, 已写下的段文件留着续传.
  Future<int?> _fetchPlan({
    required Uri uri,
    required File target,
    required SegmentPlan plan,
    required CancelToken cancelToken,
    required void Function(int received, int total) onProgress,
  }) async {
    cancelToken.throwIfCancellationRequested();
    final count = plan.ranges.length;
    final have = <int>[];
    for (var index = 0; index < count; index++) {
      final file = DownloadSegments.segment(target, index);
      final length = await file.exists() ? await file.length() : 0;
      // 超长的段说明内容不可信, 从该段开头重下.
      have.add(length <= plan.length(index) ? length : 0);
    }
    var received = have.fold<int>(0, (sum, value) => sum + value);
    onProgress(received, plan.total);
    final tokens = [for (var index = 0; index < count; index++) CancelToken()];
    var stopping = false;
    var invalid = false;
    Object? failure;
    StackTrace? failureTrace;
    void stop() {
      stopping = true;
      for (final token in tokens) {
        if (!token.isCancelled) {
          token.cancel('分段下载中止');
        }
      }
    }

    // 用户暂停时把取消转给各段.
    unawaited(
      cancelToken.whenCancel.then((_) {
        if (!stopping) {
          stop();
        }
      }),
    );
    final futures = <Future<void>>[
      for (var index = 0; index < count; index++)
        _fetchSegment(
          uri: uri,
          file: DownloadSegments.segment(target, index),
          range: plan.ranges[index],
          total: plan.total,
          have: have[index],
          sniff: index == 0,
          cancelToken: tokens[index],
          onProgress: (got) {
            received += got - have[index];
            have[index] = got;
            if (!stopping) {
              onProgress(received, plan.total);
            }
          },
        ).catchError((Object error, StackTrace stackTrace) {
          if (stopping) {
            return;
          }
          if (error is _PlanInvalid) {
            invalid = true;
          } else {
            failure = error;
            failureTrace = stackTrace;
          }
          stop();
        }),
    ];
    await Future.wait(futures);
    cancelToken.throwIfCancellationRequested();
    if (invalid) {
      return null;
    }
    if (failure case final error?) {
      Error.throwWithStackTrace(error, failureTrace ?? StackTrace.current);
    }
    final sink = target.openWrite();
    try {
      for (var index = 0; index < count; index++) {
        await sink.addStream(DownloadSegments.segment(target, index).openRead());
      }
    } finally {
      await sink.close();
    }
    final length = await target.length();
    if (length != plan.total) {
      throw FormatException('合并后的缓存大小不符, 预期 ${plan.total} 字节, 实际 $length 字节');
    }
    await DownloadSegments.clear(target);
    return length;
  }

  /// 把 [range] 中还没下的部分追加到 [file]. 服务端文件已变时抛 [_PlanInvalid].
  Future<void> _fetchSegment({
    required Uri uri,
    required File file,
    required SegmentRange range,
    required int total,
    required int have,
    required bool sniff,
    required CancelToken cancelToken,
    required void Function(int received) onProgress,
  }) async {
    final expected = range.end - range.start + 1;
    if (have >= expected) {
      return;
    }
    cancelToken.throwIfCancellationRequested();
    final from = range.start + have;
    final response = await _dio.getUri<ResponseBody>(
      uri,
      cancelToken: cancelToken,
      options: Options(
        responseType: ResponseType.stream,
        headers: _headers(range: 'bytes=$from-${range.end}'),
        validateStatus: (_) => true,
      ),
    );
    final body = response.data;
    if (body == null) {
      throw const FormatException('下载响应为空');
    }
    RandomAccessFile? output;
    var streamStarted = false;
    try {
      cancelToken.throwIfCancellationRequested();
      final status = response.statusCode;
      if (status == 200 || status == 416) {
        throw const _PlanInvalid();
      }
      if (status != 206) {
        throw FormatException('下载失败, 收到状态码 $status');
      }
      final served = _parseContentRange(response.headers.value('content-range'));
      if (served == null || served.start != from || served.total != total) {
        Log.w('分段响应区间与计划不符: ${response.headers.value('content-range')}');
        throw const _PlanInvalid();
      }
      _rejectPlaylistPath(response.realUri);
      _validateMime(response.headers.value(Headers.contentTypeHeader));
      if (have > 0) {
        output = await file.open(mode: FileMode.append);
        await output.truncate(have);
        await output.setPosition(have);
      } else {
        output = await file.open(mode: FileMode.write);
      }
      var received = have;
      final prefix = <int>[];
      streamStarted = true;
      await for (final chunk in body.stream) {
        cancelToken.throwIfCancellationRequested();
        if (chunk.isEmpty) continue;
        // 只有第一段从文件开头起, 才能嗅探内容是不是错误页.
        if (sniff && have == 0 && prefix.length < 512) {
          prefix.addAll(chunk.take(512 - prefix.length));
          _sniff(prefix);
        }
        if (received + chunk.length > expected) {
          throw const FormatException('分段响应超过预期长度');
        }
        await output.writeFrom(chunk);
        received += chunk.length;
        onProgress(received);
        cancelToken.throwIfCancellationRequested();
      }
      cancelToken.throwIfCancellationRequested();
      if (received != expected) {
        throw DownloadInterruptedException(
          '分段下载中断, 预期 $expected 字节, 实际 $received 字节',
        );
      }
    } finally {
      try {
        if (!streamStarted) {
          await body.stream.listen((_) {}).cancel();
        }
      } finally {
        await output?.close();
      }
    }
  }

  /// 解析 `bytes 100-999/1000`, 总长未知时 `total` 为 -1.
  static ({int start, int total})? _parseContentRange(String? value) {
    final match = RegExp(
      r'^bytes\s+(\d+)-(\d+)/(\d+|\*)$',
    ).firstMatch(value?.trim() ?? '');
    if (match == null) {
      return null;
    }
    final start = int.parse(match.group(1)!);
    final rawTotal = match.group(3)!;
    return (start: start, total: rawTotal == '*' ? -1 : int.parse(rawTotal));
  }

  static void _rejectPlaylistPath(Uri uri) {
    if (uri.path.toLowerCase().endsWith('.m3u8')) {
      throw const FormatException('不支持下载 HLS 播放列表, 请使用单文件媒体链接');
    }
  }

  static void _validateMime(String? value) {
    final mime = value?.split(';').first.trim().toLowerCase() ?? '';
    if (mime.isEmpty) return;
    if (mime.contains('mpegurl') || mime.contains('playlist')) {
      throw const FormatException('下载响应是播放列表, 不是单文件媒体');
    }
    if (mime.contains('html')) {
      throw const FormatException('下载响应是 HTML 页面, 不是媒体文件');
    }
    if (mime.contains('json')) {
      throw const FormatException('下载响应是 JSON 数据, 不是媒体文件');
    }
    if (!mime.startsWith('video/') &&
        !mime.startsWith('audio/') &&
        mime != 'application/octet-stream') {
      throw FormatException('不支持下载此响应类型: $mime');
    }
  }

  static void _sniff(List<int> prefix) {
    final text = utf8
        .decode(prefix, allowMalformed: true)
        .replaceFirst(RegExp(r'^\uFEFF'), '')
        .trimLeft()
        .toLowerCase();
    if (text.startsWith('{') || text.startsWith('[')) {
      throw const FormatException('下载内容是 JSON 数据, 不是媒体文件');
    }
    if (text.startsWith('#extm3u')) {
      throw const FormatException('下载内容是 HLS 播放列表, 不是单文件媒体');
    }
    if (RegExp(r'^<(?:!doctype\s+html|html\b|head\b|body\b)').hasMatch(text)) {
      throw const FormatException('下载内容是 HTML 页面, 不是媒体文件');
    }
    if (text.startsWith('<?php') ||
        RegExp(
          r'^(?:<br\s*/?>\s*)?(?:<b>)?(?:php\s+)?(?:warning|notice|fatal error|parse error)(?:</b>)?\s*:',
        ).hasMatch(text)) {
      throw const FormatException('下载内容是 PHP 文本或错误页面, 不是媒体文件');
    }
  }
}

/// Dio 的 CancelToken 不提供同步抛出方法, 保留它生成的取消异常.
extension _CancellationCheck on CancelToken {
  void throwIfCancellationRequested() {
    final error = cancelError;
    if (error != null) throw error;
  }
}
