import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';
import 'package:tucao/build_config.dart';

/// 全局日志出口.
///
/// 发布包默认只输出 info 及以上级别, 调试构建或开启 DEBUG_LOG 后输出全部级别.
abstract final class Log {
  static final Logger _logger = Logger(
    filter: _LogFilter(),
    printer: PrettyPrinter(
      methodCount: 0,
      errorMethodCount: 6,
      lineLength: 100,
      colors: false,
      printEmojis: false,
      dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
    ),
    output: _LogOutput(),
  );

  static void t(String message) => _logger.t(message);

  static void d(String message) => _logger.d(message);

  static void i(String message) => _logger.i(message);

  static void w(String message) => _logger.w(message);

  static void e(String message, {Object? error, StackTrace? stackTrace}) =>
      _logger.e(message, error: error, stackTrace: stackTrace);
}

class _LogFilter extends LogFilter {
  @override
  bool shouldLog(LogEvent event) {
    if (kReleaseMode && !BuildConfig.debugLog) {
      return event.level.index >= Level.info.index;
    }
    return true;
  }
}

class _LogOutput extends LogOutput {
  @override
  void output(OutputEvent event) {
    for (final line in event.lines) {
      developer.log(line, name: 'tucao');
    }
    if (!kReleaseMode) {
      for (final line in event.lines) {
        debugPrint(line);
      }
    }
  }
}
