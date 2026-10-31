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

/// 高能段的密度门槛, 相对峰值.
const danmakuPeakThreshold = 0.6;

/// 跳到高能段时提前的秒数, 留一点铺垫.
const danmakuPeakLeadSeconds = 2.0;

const _peakSeekTolerance = 0.5;

/// 在 [trend] 里找当前位置之后的下一个高能段, 返回应跳到的秒数.
///
/// 连续不低于 [threshold] 的点算一段, 跳转点是段起点再提前 [leadSeconds].
/// 跳转点不在当前位置之后的段都跳过, 所以连按会一段一段往后走.
/// 后面没有高能段时返回 null.
double? nextDanmakuPeak({
  required List<double> trend,
  required double durationSeconds,
  required double positionSeconds,
  double threshold = danmakuPeakThreshold,
  double leadSeconds = danmakuPeakLeadSeconds,
}) {
  if (trend.isEmpty || !durationSeconds.isFinite || durationSeconds <= 0) {
    return null;
  }
  final step = durationSeconds / trend.length;
  var index = 0;
  while (index < trend.length) {
    if (trend[index] < threshold) {
      index++;
      continue;
    }
    final start = index;
    while (index < trend.length && trend[index] >= threshold) {
      index++;
    }
    final target = (start * step - leadSeconds).clamp(0.0, durationSeconds);
    // 正在这一段里, 刚跳到这一段的铺垫处, 或已经过了, 都继续往后找.
    // 留半秒余量, 跳转落点通常不精确.
    if (target <= positionSeconds + _peakSeekTolerance) {
      continue;
    }
    return target;
  }
  return null;
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
