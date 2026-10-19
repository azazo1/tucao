import 'package:flutter/material.dart';

/// 对白用真实文字, 气泡只负责装饰, 支持字体缩放和读屏.
class ComicSpeechBubble extends StatelessWidget {
  const ComicSpeechBubble({
    super.key,
    required this.child,
    required this.fill,
    required this.ink,
  });

  final Widget child;
  final Color fill;
  final Color ink;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _BubblePainter(fill: fill, ink: ink),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
        child: child,
      ),
    );
  }
}

class _BubblePainter extends CustomPainter {
  const _BubblePainter({required this.fill, required this.ink});

  final Color fill;
  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(1, 1, size.width - 2, size.height - 15),
      const Radius.circular(22),
    );
    canvas.drawRRect(body, Paint()..color = fill);
    canvas.drawRRect(
      body,
      Paint()
        ..color = ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );
    final x = size.width * 0.52;
    final y = size.height - 14;
    final tail = Path()
      ..moveTo(x - 12, y - 1)
      ..lineTo(x - 2, size.height - 1)
      ..lineTo(x + 14, y - 1)
      ..close();
    canvas.drawPath(tail, Paint()..color = fill);
    final edge = Path()
      ..moveTo(x - 12, y)
      ..lineTo(x - 2, size.height - 1)
      ..lineTo(x + 14, y);
    canvas.drawPath(
      edge,
      Paint()
        ..color = ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_BubblePainter oldDelegate) =>
      fill != oldDelegate.fill || ink != oldDelegate.ink;
}
