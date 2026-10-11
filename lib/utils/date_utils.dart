import 'package:intl/intl.dart';

/// 时间显示.
abstract final class DateUtil {
  static final _full = DateFormat('yyyy-MM-dd HH:mm');
  static final _day = DateFormat('yyyy-MM-dd');
  static final _short = DateFormat('MM-dd');

  /// 秒级时间戳格式化为相对时间, 超过一周显示具体日期.
  static String relative(int seconds) {
    if (seconds <= 0) {
      return '';
    }
    final time = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
    final now = DateTime.now();
    final diff = now.difference(time);
    if (diff.inMinutes < 1) {
      return '刚刚';
    }
    if (diff.inHours < 1) {
      return '${diff.inMinutes}分钟前';
    }
    if (diff.inDays < 1) {
      return '${diff.inHours}小时前';
    }
    if (diff.inDays < 7) {
      return '${diff.inDays}天前';
    }
    if (time.year == now.year) {
      return _short.format(time);
    }
    return _day.format(time);
  }

  /// 秒级时间戳格式化为完整时间.
  static String full(int seconds) {
    if (seconds <= 0) {
      return '';
    }
    return _full.format(
      DateTime.fromMillisecondsSinceEpoch(seconds * 1000),
    );
  }

  /// 当前时间戳, 秒.
  static int nowSeconds() => DateTime.now().millisecondsSinceEpoch ~/ 1000;
}
