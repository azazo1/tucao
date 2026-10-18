import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:tucao/common/vip.dart';

/// 破会员的金色流光.
///
/// 站点给破会员的昵称配的是 `#c07c32`, 客户端只借它认人, 展示上换成会
/// 流动的金色, 再撒几颗小粒子, 破会员在页面里一眼就能看出来.
///
/// [child] 的不透明像素都会被金色渐变接管, 因此传进来的可以是一段文字, 也可以是
/// 一整块带底色和描边的标签: 底色按自己的透明度跟着渐变走, 文字保持实心, 两者
/// 仍然分得清.
///
/// 系统开了减弱动画时不跑流光与粒子, 只留一层静止的金色渐变.
class VipGold extends StatefulWidget {
  const VipGold({
    super.key,
    required this.child,
    this.particleCount = 6,
    this.particleSeed = 0,
  });

  final Widget child;

  /// 粒子数量, 传 0 就只要流光.
  final int particleCount;

  /// 粒子分布的随机种子, 同一处传同一个值, 粒子位置才稳定.
  final int particleSeed;

  @override
  State<VipGold> createState() => _VipGoldState();
}

class _VipGoldState extends State<VipGold> with SingleTickerProviderStateMixin {
  /// 一轮扫光的时长, 比常见的骨架屏慢一些, 免得晃眼.
  static const _period = Duration(milliseconds: 2400);

  /// 减弱动画时停下的位置, 正好让扫光带压在文字上.
  static const _restingProgress = 0.5;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _period,
  );

  late List<_Sparkle> _sparkles = _spreadSparkles();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_reduceMotion) {
      _controller.stop();
      _controller.value = _restingProgress;
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(VipGold oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.particleCount != widget.particleCount ||
        oldWidget.particleSeed != widget.particleSeed) {
      _sparkles = _spreadSparkles();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _reduceMotion =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  List<_Sparkle> _spreadSparkles() {
    final random = math.Random(widget.particleSeed);
    return [
      for (var i = 0; i < widget.particleCount; i++) _Sparkle.random(random),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        return Stack(
          // 粒子会飘出文字框一点点, 这里不做裁剪.
          clipBehavior: Clip.none,
          children: [
            ShaderMask(
              blendMode: BlendMode.srcIn,
              shaderCallback: (bounds) =>
                  _shimmerGradient(_controller.value).createShader(bounds),
              child: child,
            ),
            if (widget.particleCount > 0)
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _SparklePainter(
                      progress: _controller.value,
                      sparkles: _sparkles,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// 一条亮带在金色底子上从左扫到右.
///
/// 渐变两端都是底色, 平移到画面外的部分由着色器的 clamp 补上底色, 所以扫光带
/// 进出文字时不会露出断层, 循环播放也接得上.
LinearGradient _shimmerGradient(double progress) {
  return LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: const [
      Vip.goldDeep,
      Vip.gold,
      Vip.goldBright,
      Vip.goldShine,
      Vip.goldBright,
      Vip.gold,
      Vip.goldDeep,
    ],
    stops: const [0, 0.2, 0.38, 0.5, 0.62, 0.8, 1],
    transform: _SlideTransform(progress * 2 - 1),
  );
}

/// 把渐调整体左右平移, [shift] 是 -1 到 1 的比例.
class _SlideTransform extends GradientTransform {
  const _SlideTransform(this.shift);

  final double shift;

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    return Matrix4.translationValues(bounds.width * shift, 0, 0);
  }
}

/// 一颗粒子, 位置用 0 到 1 的相对坐标记, 换尺寸不用重新算.
class _Sparkle {
  const _Sparkle({
    required this.x,
    required this.y,
    required this.radius,
    required this.phase,
    required this.rise,
  });

  factory _Sparkle.random(math.Random random) => _Sparkle(
    x: random.nextDouble(),
    y: 0.15 + random.nextDouble() * 0.85,
    radius: 0.5 + random.nextDouble() * 0.7,
    phase: random.nextDouble(),
    rise: 0.25 + random.nextDouble() * 0.35,
  );

  final double x;
  final double y;

  /// 半径, 单位是逻辑像素.
  final double radius;

  /// 相位, 让每颗粒子错开闪烁.
  final double phase;

  /// 一个周期里上浮的高度, 相对组件高度.
  final double rise;
}

/// 把粒子画成向上飘的闪光.
class _SparklePainter extends CustomPainter {
  _SparklePainter({required this.progress, required this.sparkles});

  final double progress;
  final List<_Sparkle> sparkles;

  @override
  void paint(Canvas canvas, Size size) {
    final dot = Paint();
    final star = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.7
      ..strokeCap = StrokeCap.round;
    for (final sparkle in sparkles) {
      final t = (progress + sparkle.phase) % 1;
      // 两头淡中间亮, 粒子是闪一下再消失, 而不是突然冒出来.
      final fade = math.sin(t * math.pi);
      if (fade < 0.05) {
        continue;
      }
      final center = Offset(
        sparkle.x * size.width,
        sparkle.y * size.height - size.height * sparkle.rise * t,
      );
      final color = Color.lerp(
        Vip.gold,
        Vip.goldShine,
        fade,
      )!.withValues(alpha: 0.9 * fade);
      if (sparkle.radius > 0.9) {
        // 大一点的画成四芒星, 小的是圆点, 画面才有层次.
        star.color = color;
        final arm = sparkle.radius * 2.4;
        canvas.drawLine(
          Offset(center.dx - arm, center.dy),
          Offset(center.dx + arm, center.dy),
          star,
        );
        canvas.drawLine(
          Offset(center.dx, center.dy - arm),
          Offset(center.dx, center.dy + arm),
          star,
        );
      } else {
        dot.color = color;
        canvas.drawCircle(center, sparkle.radius, dot);
      }
    }
  }

  @override
  bool shouldRepaint(_SparklePainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.sparkles != sparkles;
}
