/// 高能条的点数参数.
///
/// 点数随视频时长变化: 短视频不至于一个点跨好几秒, 长视频也不会画出上千个点.
const danmakuTrendMinPoints = 24;
const danmakuTrendMaxPoints = 120;
const danmakuTrendSecondsPerPoint = 3.0;

/// 统计弹幕在时间轴上的密度, 返回 [0, 1] 的密度序列.
///
/// [times] 是弹幕出现的秒数, 超出 [durationSeconds] 的弹幕直接丢弃, 站点偶尔
/// 会有这种对不上时长的数据. 返回值按峰值归一化, 峰值点顶满高能条, 便于看出
/// 节奏起伏.
///
/// 返回空列表表示没有可用数据: 时长或点间隔非法, 或者落在时长内的弹幕一条也
/// 没有, 此时界面不画高能条.
List<double> buildDanmakuTrend({
  required Iterable<double> times,
  required double durationSeconds,
  int minPoints = danmakuTrendMinPoints,
  int maxPoints = danmakuTrendMaxPoints,
  double secondsPerPoint = danmakuTrendSecondsPerPoint,
}) {
  if (!durationSeconds.isFinite || durationSeconds <= 0) {
    return const [];
  }
  if (!secondsPerPoint.isFinite || secondsPerPoint <= 0) {
    return const [];
  }
  final pointCount = _pointCount(
    durationSeconds,
    minPoints,
    maxPoints,
    secondsPerPoint,
  );
  final counts = List<double>.filled(pointCount, 0);
  var inside = 0;
  for (final time in times) {
    if (!time.isFinite || time < 0 || time >= durationSeconds) {
      continue;
    }
    final index = (time / durationSeconds * pointCount)
        .floor()
        .clamp(0, pointCount - 1)
        .toInt();
    counts[index] += 1;
    inside++;
  }
  if (inside == 0) {
    return const [];
  }
  var peak = 0.0;
  for (final value in counts) {
    if (value > peak) {
      peak = value;
    }
  }
  if (peak <= 0) {
    return const [];
  }
  return [for (final value in counts) value / peak];
}

int _pointCount(
  double durationSeconds,
  int minPoints,
  int maxPoints,
  double secondsPerPoint,
) {
  final raw = (durationSeconds / secondsPerPoint).floor();
  if (raw < minPoints) {
    return minPoints;
  }
  if (raw > maxPoints) {
    return maxPoints;
  }
  return raw;
}
