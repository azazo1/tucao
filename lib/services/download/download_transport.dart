import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:tucao/common/constants.dart';
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
  Future<int> fetch({
    required Uri uri,
    required File target,
    required CancelToken cancelToken,
    required void Function(int received, int total) onProgress,
    int offset = 0,
    int expectedTotal = -1,
  });
}

/// 使用公共 Dio 客户端的拦截器, 不创建目录或提交最终文件.
class DioDownloadTransport implements DownloadTransport {
  DioDownloadTransport(this._dio);

  final Dio _dio;

  @override
  Future<int> fetch({
    required Uri uri,
    required File target,
    required CancelToken cancelToken,
    required void Function(int received, int total) onProgress,
    int offset = 0,
    int expectedTotal = -1,
  }) async {
    if (offset > 0) {
      final resumed = await _fetchOnce(
        uri: uri,
        target: target,
        cancelToken: cancelToken,
        onProgress: onProgress,
        offset: offset,
        expectedTotal: expectedTotal,
      );
      if (resumed != null) {
        return resumed;
      }
      Log.w('续传条件不满足, 从头下载: $uri');
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
        headers: {
          'user-agent': Constants.userAgent,
          'referer': Constants.baseUrl,
          if (resume) 'range': 'bytes=$offset-',
        },
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
