/// 番剧每周固定的更新时刻.
///
/// 站点把时刻写在播放页的番组信息里, 形如 `更新：星期天，01:50`,
/// 首页时间表只有集数状态, 因此时刻要单独从播放页取, 见
/// `WeekUpdateTimeService`.
class WeekUpdateTime {
  const WeekUpdateTime({required this.hour, required this.minute});

  /// 小时, 0 到 23.
  final int hour;

  /// 分钟, 0 到 59.
  final int minute;

  /// 当天的分钟数, 排序用.
  int get minutesOfDay => hour * 60 + minute;

  /// 当天的这个时刻是否已经到过.
  ///
  /// 只对当天的分组有意义: 别的日子没有 "现在" 可比, 调用方自行限制.
  bool hasReached(DateTime now) => now.hour * 60 + now.minute >= minutesOfDay;

  /// 显示用的时刻, 形如 `01:50`.
  String get label =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  /// 匹配 `01:50` 或 `1:50`, 兼容全角冒号.
  static final _clock = RegExp(r'(\d{1,2})\s*[:：]\s*(\d{2})');

  /// 从 "星期天，01:50" 这类文本里取时刻, 取不到时返回 null.
  ///
  /// 剧场版与部分天朝番没有更新时刻, 页面上干脆没有这一项, 调用方按
  /// null 处理即可.
  static WeekUpdateTime? parse(String raw) {
    final match = _clock.firstMatch(raw);
    if (match == null) {
      return null;
    }
    final hour = int.tryParse(match.group(1)!);
    final minute = int.tryParse(match.group(2)!);
    if (hour == null || minute == null || hour > 23 || minute > 59) {
      return null;
    }
    return WeekUpdateTime(hour: hour, minute: minute);
  }

  @override
  String toString() => label;
}
