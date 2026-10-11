/// 数值与时长的格式化.
abstract final class Utils {
  /// 播放数等大数字, 超过一万时按站点习惯显示为 `1.2万`.
  static String formatCount(int count) {
    if (count < 10000) {
      return count.toString();
    }
    if (count < 100000000) {
      final value = count / 10000;
      return '${_trim(value)}万';
    }
    return '${_trim(count / 100000000)}亿';
  }

  static String _trim(double value) {
    final text = value.toStringAsFixed(1);
    return text.endsWith('.0') ? text.substring(0, text.length - 2) : text;
  }

  /// 秒数格式化为 `mm:ss` 或 `hh:mm:ss`.
  static String formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    final mm = minutes.toString().padLeft(2, '0');
    final ss = seconds.toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$mm:$ss' : '$mm:$ss';
  }

  /// 秒数格式化, 入参为 double.
  static String formatSeconds(double seconds) =>
      formatDuration(Duration(milliseconds: (seconds * 1000).round()));

  /// 文件大小.
  static String formatBytes(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    }
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
  }
}
