import 'package:flutter_test/flutter_test.dart';
import 'package:tucao/plugin/player/danmaku_trend.dart';

void main() {
  test('时长非法时没有数据', () {
    expect(buildDanmakuTrend(times: const [1, 2], durationSeconds: 0), isEmpty);
    expect(
      buildDanmakuTrend(times: const [1, 2], durationSeconds: double.nan),
      isEmpty,
    );
  });

  test('点间隔非法时没有数据', () {
    expect(
      buildDanmakuTrend(
        times: const [1],
        durationSeconds: 60,
        secondsPerPoint: 0,
      ),
      isEmpty,
    );
  });

  test('点数随时长收敛在上下限之间', () {
    expect(
      buildDanmakuTrend(times: const [1], durationSeconds: 30).length,
      danmakuTrendMinPoints,
    );
    expect(
      buildDanmakuTrend(times: const [1], durationSeconds: 7200).length,
      danmakuTrendMaxPoints,
    );
  });

  test('按峰值归一化, 其余时段保持为 0', () {
    final trend = buildDanmakuTrend(
      times: const [1, 1.2, 1.4, 599],
      durationSeconds: 600,
    );
    expect(trend.length, danmakuTrendMaxPoints);
    expect(trend.first, 1);
    expect(trend.last, moreOrLessEquals(1 / 3));
    expect(
      trend.sublist(1, trend.length - 1).every((value) => value == 0),
      isTrue,
    );
  });

  test('超出时长的弹幕被丢弃', () {
    final trend = buildDanmakuTrend(
      times: const [600, -1, double.infinity],
      durationSeconds: 600,
    );
    expect(trend, isEmpty);
  });

  test('连按跳高能一段段往后走, 跳到铺垫处后不原地打转, 末尾返回空', () {
    // 每点 10 秒: 第 2-3 点与第 6 点是高能段.
    const trend = [0.1, 0.2, 0.9, 1.0, 0.3, 0.1, 0.7, 0.2];
    double? next(double position) => nextDanmakuPeak(
      trend: trend,
      durationSeconds: 80,
      positionSeconds: position,
    );
    expect(next(0), 18);
    // 跳转落点比目标略早或略晚都算已到达这一段.
    expect(next(17.8), 58);
    expect(next(18.3), 58);
    // 正在第一段里.
    expect(next(25), 58);
    expect(next(58), isNull);
  });
}
