import 'package:flutter/material.dart';

/// 续命进度条.
///
/// 站点把广告收益折算成天数, 再把天数当成百分数直接画长度, 因此
/// `7.85天` 只占整条的 7.85%, 数值小的时候细得看不见.
/// 这里沿用站点的数字, 只加一个最小可见长度, 让有贡献的条目都能看出来.
class LifeProgressBar extends StatelessWidget {
  const LifeProgressBar({
    super.key,
    required this.ratio,
    this.height = 6,
    this.minVisibleRatio = 0.02,
  });

  /// 0 到 1 之间的占比, 超出范围会被截断.
  final double ratio;

  final double height;

  /// 大于零的占比至少画这么长, 免得细成一根头发.
  final double minVisibleRatio;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final value = ratio.isFinite ? ratio.clamp(0.0, 1.0) : 0.0;
    final visible = value <= 0
        ? 0.0
        : value.clamp(minVisibleRatio, 1.0).toDouble();
    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: SizedBox(
        height: height,
        child: Stack(
          children: [
            Positioned.fill(
              child: ColoredBox(color: scheme.surfaceContainerHighest),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: visible,
                heightFactor: 1,
                child: ColoredBox(color: scheme.primary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
