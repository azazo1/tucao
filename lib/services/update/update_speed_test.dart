import 'dart:async';

import 'package:dio/dio.dart';
import 'package:tucao/models/update_mirror.dart';
import 'package:tucao/utils/logger.dart';

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
    this.timedOut = false,
  });

  /// 实际读到的字节数.
  final int bytes;

  /// 从发请求到读够探测字节的耗时.
  final Duration elapsed;

  /// 首个数据块到达的耗时, 可以用来观察连接建立速度.
  final Duration? firstByte;

  /// 失败原因, 为空表示测速成功.
  final String? error;

  /// 是否在读完探测字节前就到了时限.
  ///
  /// 这时速度按已经读到的那部分估算, 比直接报失败更有参考价值.
  final bool timedOut;

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
    final speed = '${kilobytes.toStringAsFixed(kilobytes >= 100 ? 0 : 1)} KB/s';
    return timedOut ? '$speed (未测完)' : speed;
  }
}

/// 镜像源测速.
///
/// 用安装包里固定的一段做探测, 不下载整个包, 也不会写入任何文件.
/// 失败的镜像只影响自己的测速结果, 不影响其他源.
abstract final class UpdateSpeedTest {
  /// 每次测速读取的字节数.
  ///
  /// 只取半个兆, 慢站在时限内也能读到一部分, 不至于一个字节都报不出来.
  static const probeBytes = 512 * 1024;

  /// 单次测速的超时时间.
  static const timeout = Duration(seconds: 12);

  static final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: timeout,
    ),
  );

  /// 探测 [mirror] 对 [targetUrl] 的下载速度.
  static Future<MirrorSpeedResult> measure({
    required UpdateMirror mirror,
    required String targetUrl,
    Dio? dio,
  }) async {
    final token = CancelToken();
    Log.i('镜像测速开始 ${mirror.prefix}');
    try {
      // 流内部的时限负责保留已读数据, 这里只是连接阶段卡死时的兜底.
      final result = await _measure(
        mirror,
        targetUrl,
        dio ?? _dio,
        token,
      ).timeout(timeout + const Duration(seconds: 4));
      Log.i(
        '镜像测速结果 ${mirror.prefix}: ${result.text}, '
        '${result.bytes} 字节, 耗时 ${result.elapsed.inMilliseconds}ms, '
        '首字节 ${result.firstByte?.inMilliseconds ?? -1}ms',
      );
      return result;
    } on TimeoutException {
      token.cancel('测速超时');
      Log.w('镜像测速超时 ${mirror.prefix}');
      return const MirrorSpeedResult(error: '测速超时');
    } catch (error) {
      final message = _errorText(error);
      Log.w('镜像测速失败 ${mirror.prefix}: $message ($error)');
      return MirrorSpeedResult(error: message);
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
    var timedOut = false;
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
      if (watch.elapsed >= timeout) {
        // 到时限还没读够, 保留已读部分, 速度按这段估算.
        timedOut = true;
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
      timedOut: timedOut && bytes < probeBytes,
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
