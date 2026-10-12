import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:tucao/common/constants.dart';

/// 单文件媒体传输, 文件目录与最终提交由下载服务负责.
abstract class DownloadTransport {
  Future<int> fetch({
    required Uri uri,
    required File target,
    required CancelToken cancelToken,
    required void Function(int received, int total) onProgress,
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
  }) async {
    cancelToken.throwIfCancellationRequested();
    _rejectPlaylistPath(uri);
    final response = await _dio.getUri<ResponseBody>(
      uri,
      cancelToken: cancelToken,
      options: Options(
        responseType: ResponseType.stream,
        headers: {
          'user-agent': Constants.userAgent,
          'referer': Constants.baseUrl,
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
      if (response.statusCode != 200) {
        throw FormatException('下载仅支持 HTTP 200, 收到 ${response.statusCode}');
      }
      _rejectPlaylistPath(response.realUri);
      _validateMime(response.headers.value(Headers.contentTypeHeader));
      final lengthHeader = response.headers.value(Headers.contentLengthHeader);
      final total = lengthHeader == null ? -1 : int.tryParse(lengthHeader);
      if (total == null || (lengthHeader != null && total < 0)) {
        throw const FormatException('下载响应的 Content-Length 无效');
      }
      output = await target.open(mode: FileMode.write);
      var received = 0;
      final prefix = <int>[];
      streamStarted = true;
      await for (final chunk in body.stream) {
        cancelToken.throwIfCancellationRequested();
        if (chunk.isEmpty) continue;
        // 只保留首部小段, 同时识别跨网络分块拆开的文本标记.
        if (prefix.length < 512) {
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
        throw FormatException('下载不完整, 预期 $total 字节, 实际 $received 字节');
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
