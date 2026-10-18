import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tucao/pages/ad/ad_list_page.dart';

/// 首页标题栏里的广告入口.
///
/// 没有背景, 与普通图标一致; 只有礼物图标本身做斜向炫彩渐变,
/// 周围漂浮少量灰尘一样的闪光粒子. 点击进入应用内广告列表.
class AdEntryButton extends StatefulWidget {
  const AdEntryButton({super.key});

  @override
  State<AdEntryButton> createState() => _AdEntryButtonState();
}

class _AdEntryButtonState extends State<AdEntryButton>
    with SingleTickerProviderStateMixin {
  static const _visualSize = 40.0;
  static const _iconSize = 24.0;

  /// 斜向渐变的色标, 顺序即左上到右下.
  static const _colors = <Color>[
    Color(0xFFFF7A7A),
    Color(0xFFFF9F5A),
    Color(0xFFFFD166),
    Color(0xFFA8E063),
    Color(0xFF4DD4AC),
    Color(0xFF4DABF7),
    Color(0xFF9B7BFF),
    Color(0xFFFF7AD9),
  ];

  late final AnimationController _controller;
  late final List<_Dust> _dust;

  bool _reducedMotion = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat();
    final random = math.Random(7);
    _dust = List.generate(10, (_) => _Dust.random(random));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = MediaQuery.disableAnimationsOf(context);
    if (reduced == _reducedMotion) {
      return;
    }
    _reducedMotion = reduced;
    if (reduced) {
      _controller.stop();
    } else {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<Color> _gradientColors(double progress) {
    final shift = progress * 360;
    return [
      for (final color in _colors)
        HSVColor.fromColor(color)
            .withHue((HSVColor.fromColor(color).hue + shift) % 360)
            .toColor(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '广告',
      child: Tooltip(
        message: '广告',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => Get.to(() => const AdListPage()),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: SizedBox(
              width: _visualSize,
              height: _visualSize,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (!_reducedMotion)
                    AnimatedBuilder(
                      animation: _controller,
                      builder: (context, child) => CustomPaint(
                        size: const Size(_visualSize, _visualSize),
                        painter: _DustPainter(
                          progress: _controller.value,
                          particles: _dust,
                        ),
                      ),
                    ),
                  AnimatedBuilder(
                    animation: _controller,
                    builder: (context, child) => ShaderMask(
                      blendMode: BlendMode.srcIn,
                      shaderCallback: (rect) => LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: _gradientColors(_controller.value),
                      ).createShader(rect),
                      child: const Icon(
                        Icons.redeem,
                        size: _iconSize,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 一颗灰尘粒子.
class _Dust {
  const _Dust({
    required this.start,
    required this.velocity,
    required this.phase,
    required this.radius,
    required this.color,
  });

  /// 相对图标中心的初始偏移.
  final Offset start;

  /// 一个生命周期内的漂移量.
  final Offset velocity;

  final double phase;
  final double radius;
  final Color color;

  static const _palette = <Color>[
    Colors.white,
    Color(0xFFFFD166),
    Color(0xFF5EE7FF),
    Color(0xFFFF5D8F),
  ];

  static _Dust random(math.Random random) {
    final angle = random.nextDouble() * math.pi * 2;
    // 半径比 24px 图标略大一点, 不向外散开.
    final distance = 13 + random.nextDouble() * 4;
    return _Dust(
      start: Offset(
        math.cos(angle) * distance,
        math.sin(angle) * distance,
      ),
      velocity: Offset(
        (random.nextDouble() - 0.5) * 3,
        (random.nextDouble() - 0.5) * 3,
      ),
      phase: random.nextDouble(),
      radius: 0.4 + random.nextDouble() * 0.9,
      color: _palette[random.nextInt(_palette.length)],
    );
  }
}

class _DustPainter extends CustomPainter {
  _DustPainter({required this.progress, required this.particles});

  final double progress;
  final List<_Dust> particles;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final paint = Paint()..blendMode = BlendMode.plus;
    for (final particle in particles) {
      final age = (progress * 3 + particle.phase) % 1.0;
      final alpha = math.sin(math.pi * age);
      if (alpha <= 0.01) {
        continue;
      }
      final position = center + particle.start + particle.velocity * age;
      paint
        ..color = particle.color.withValues(alpha: alpha * 0.85)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.2);
      canvas.drawCircle(position, particle.radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _DustPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.particles != particles;
}
