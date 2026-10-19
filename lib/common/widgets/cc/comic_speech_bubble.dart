import 'package:flutter/material.dart';

/// 气泡尾巴的方向: 人物在气泡下方时朝下, 在右侧时朝右.
enum ComicBubbleTail { bottom, right }

/// 对白用真实文字, 气泡只负责装饰, 支持字体缩放和读屏.
class ComicSpeechBubble extends StatelessWidget {
  const ComicSpeechBubble({
    super.key,
    required this.child,
    required this.fill,
    required this.ink,
    this.tail = ComicBubbleTail.bottom,
  });

  final Widget child;
  final Color fill;
  final Color ink;
  final ComicBubbleTail tail;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _BubblePainter(fill: fill, ink: ink, tail: tail),
      child: Padding(
        padding: tail == ComicBubbleTail.bottom
            ? const EdgeInsets.fromLTRB(20, 18, 20, 32)
            : const EdgeInsets.fromLTRB(20, 18, 34, 18),
        child: child,
      ),
    );
  }
}

class _BubblePainter extends CustomPainter {
  const _BubblePainter({
    required this.fill,
    required this.ink,
    required this.tail,
  });

  final Color fill;
  final Color ink;
  final ComicBubbleTail tail;

  @override
  void paint(Canvas canvas, Size size) {
    if (tail == ComicBubbleTail.right) {
      _paintRightTail(canvas, size);
      return;
    }
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
    final tailPath = Path()
      ..moveTo(x - 12, y - 1)
      ..lineTo(x - 2, size.height - 1)
      ..lineTo(x + 14, y - 1)
      ..close();
    canvas.drawPath(tailPath, Paint()..color = fill);
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

  /// 与默认的朝下尾巴同一套比例, 只把方向转到右侧.
  void _paintRightTail(Canvas canvas, Size size) {
    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(1, 1, size.width - 15, size.height - 2),
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
    final x = size.width - 15;
    final y = size.height * 0.52;
    final tailPath = Path()
      ..moveTo(x, y - 13)
      ..lineTo(size.width - 1, y - 3)
      ..lineTo(x, y + 13)
      ..close();
    canvas.drawPath(tailPath, Paint()..color = fill);
    final edge = Path()
      ..moveTo(x, y - 13)
      ..lineTo(size.width - 1, y - 3)
      ..lineTo(x, y + 13);
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
      fill != oldDelegate.fill ||
      ink != oldDelegate.ink ||
      tail != oldDelegate.tail;
}
