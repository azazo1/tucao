import 'dart:async';

import 'package:dio/dio.dart';
import 'package:tucao/models/update_mirror.dart';

/// 单个镜像源的测速结果.
///
/// 只读取安装包开头的一小段, 因此 [bytes] 不一定等于整包大小;
/// 速度按这段的字节数除以耗时计算, 用来比较各镜像站谁更快.
class MirrorSpeedResult {
  const MirrorSpeedResult({
    this.bytes = 0,
    this.elapsed = Duration.zero,
    this.firstByte,
    this.error,
  });

  /// 实际读到的字节数.
  final int bytes;

  /// 从发请求到读够探测字节的耗时.
  final Duration elapsed;

  /// 首个数据块到达的耗时, 可以用来观察连接建立速度.
  final Duration? firstByte;

  /// 失败原因, 为空表示测速成功.
  final String? error;

  bool get ok => error == null && bytes > 0;

  /// 去掉首字节等待之后的传输耗时.
  ///
  /// 建立连接与首包等待对每个站差异很大, 算进速度会把快站拉低,
  /// 因此速度按这段耗时计算, 首字节单独展示.
  Duration get transferElapsed {
    final wait = firstByte;
    if (wait == null) {
      return elapsed;
    }
    final rest = elapsed - wait;
    return rest.inMicroseconds > 0 ? rest : elapsed;
  }

  /// 每秒字节数, 耗时为零或失败时为 0.
  double get bytesPerSecond {
    final micros = transferElapsed.inMicroseconds;
    if (!ok || micros <= 0) {
      return 0;
    }
    return bytes * 1000000 / micros;
  }

  /// 速度文案, 失败时给出原因.
  String get text {
    if (!ok) {
      return error ?? '测速失败';
    }
    final kilobytes = bytesPerSecond / 1024;
    return '${kilobytes.toStringAsFixed(kilobytes >= 100 ? 0 : 1)} KB/s';
  }
}

/// 镜像源测速.
///
/// 用安装包里固定的一段做探测, 不下载整个包, 也不会写入任何文件.
/// 失败的镜像只影响自己的测速结果, 不影响其他源.
abstract final class UpdateSpeedTest {
  /// 每次测速读取的字节数.
  static const probeBytes = 1024 * 1024;

  /// 单次测速的超时时间.
  static const timeout = Duration(seconds: 8);

  static final Dio _dio = Dio(
    BaseOptions(connectTimeout: timeout, receiveTimeout: timeout),
  );

  /// 探测 [mirror] 对 [targetUrl] 的下载速度.
  static Future<MirrorSpeedResult> measure({
    required UpdateMirror mirror,
    required String targetUrl,
    Dio? dio,
  }) async {
    final token = CancelToken();
    try {
      return await _measure(
        mirror,
        targetUrl,
        dio ?? _dio,
        token,
      ).timeout(timeout);
    } on TimeoutException {
      token.cancel('测速超时');
      return const MirrorSpeedResult(error: '测速超时');
    } catch (error) {
      return MirrorSpeedResult(error: _errorText(error));
    } finally {
      if (!token.isCancelled) {
        token.cancel('测速结束');
      }
    }
  }

  static Future<MirrorSpeedResult> _measure(
    UpdateMirror mirror,
    String targetUrl,
    Dio client,
    CancelToken token,
  ) async {
    final watch = Stopwatch()..start();
    final response = await client.getUri<ResponseBody>(
      Uri.parse(mirror.urlFor(targetUrl)),
      cancelToken: token,
      options: Options(
        responseType: ResponseType.stream,
        headers: {
          'range': 'bytes=0-${probeBytes - 1}',
          'User-Agent': 'tucao-android',
        },
        // 只认正常结果, 错误页和重定向后的异常状态直接按失败处理.
        validateStatus: (code) => code == 200 || code == 206,
      ),
    );
    final body = response.data;
    if (body == null) {
      return const MirrorSpeedResult(error: '响应为空');
    }
    var bytes = 0;
    Duration? firstByte;
    await for (final chunk in body.stream) {
      if (chunk.isEmpty) {
        continue;
      }
      firstByte ??= watch.elapsed;
      bytes += chunk.length;
      // 读够探测字节就停, 不支持 Range 的站也不会把整包拖下来.
      if (bytes >= probeBytes) {
        break;
      }
    }
    if (bytes == 0) {
      return const MirrorSpeedResult(error: '没有收到数据');
    }
    return MirrorSpeedResult(
      bytes: bytes,
      elapsed: watch.elapsed,
      firstByte: firstByte,
    );
  }

  static String _errorText(Object error) {
    if (error is DioException) {
      final status = error.response?.statusCode;
      if (status != null && status != 200 && status != 206) {
        return '状态码 $status';
      }
      return switch (error.type) {
        DioExceptionType.connectionTimeout ||
        DioExceptionType.sendTimeout ||
        DioExceptionType.receiveTimeout => '连接超时',
        DioExceptionType.connectionError => '连接失败',
        _ => '测速失败',
      };
    }
    return '测速失败';
  }
}
