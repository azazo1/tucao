import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

/// 安装包的单文件传输, 目录与最终提交由下载服务负责.
///
/// 与媒体缓存分开实现: 那边的校验只放行音视频响应, 这里的产物是 apk,
/// 两者除了"边下边写"之外没有别的共同判断.
abstract class UpdateTransport {
  Future<int> fetch({
    required Uri uri,
    required File target,
    required CancelToken cancelToken,
    required void Function(int received, int total) onProgress,
  });
}

/// 使用独立 Dio 客户端的安装包传输.
class DioUpdateTransport implements UpdateTransport {
  /// 不传客户端时自建一个: 只连 GitHub, 不带站点 cookie 与 referer.
  DioUpdateTransport([Dio? dio])
    : _dio =
          dio ??
          Dio(BaseOptions(connectTimeout: const Duration(seconds: 8)));

  final Dio _dio;

  @override
  Future<int> fetch({
    required Uri uri,
    required File target,
    required CancelToken cancelToken,
    required void Function(int received, int total) onProgress,
  }) async {
    cancelToken.throwIfCancellationRequested();
    final response = await _dio.getUri<ResponseBody>(
      uri,
      cancelToken: cancelToken,
      options: Options(
        responseType: ResponseType.stream,
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
        throw FormatException('下载安装包失败, 收到状态码 ${response.statusCode}');
      }
      final lengthHeader = response.headers.value(Headers.contentLengthHeader);
      final total = lengthHeader == null ? -1 : int.tryParse(lengthHeader);
      if (total == null || total < 0) {
        throw const FormatException('下载响应的 Content-Length 无效');
      }
      output = await target.open(mode: FileMode.write);
      var received = 0;
      final prefix = <int>[];
      streamStarted = true;
      await for (final chunk in body.stream) {
        cancelToken.throwIfCancellationRequested();
        if (chunk.isEmpty) continue;
        // 只保留首部小段, 用来识别把错误页当成安装包下载的情况.
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
        throw const FormatException('下载的安装包为空');
      }
      if (total > 0 && received != total) {
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

  /// 安装包是 ZIP, 响应以文本开头就说明拿到的是错误页或接口数据.
  static void _sniff(List<int> prefix) {
    final text = utf8
        .decode(prefix, allowMalformed: true)
        .replaceFirst(RegExp(r'^\uFEFF'), '')
        .trimLeft()
        .toLowerCase();
    if (text.startsWith('{') || text.startsWith('[')) {
      throw const FormatException('下载内容是 JSON 数据, 不是安装包');
    }
    if (RegExp(r'^<(?:!doctype\s+html|html\b|head\b|body\b)').hasMatch(text)) {
      throw const FormatException('下载内容是 HTML 页面, 不是安装包');
    }
    if (text.startsWith('<?php') ||
        RegExp(
          r'^(?:<br\s*/?>\s*)?(?:<b>)?(?:php\s+)?(?:warning|notice|fatal error|parse error)(?:</b>)?\s*:',
        ).hasMatch(text)) {
      throw const FormatException('下载内容是 PHP 文本或错误页面, 不是安装包');
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
