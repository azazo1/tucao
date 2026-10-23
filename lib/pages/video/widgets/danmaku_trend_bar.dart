import 'package:flutter/material.dart';

/// 进度条上方的弹幕高能条.
///
/// [values] 是 [0, 1] 的密度序列, 从左到右对应整段视频. 只负责画, 不参与
/// 手势, 拖动进度仍然作用在下面的进度条上.
class DanmakuTrendBar extends StatelessWidget {
  const DanmakuTrendBar({super.key, required this.values, required this.color});

  /// 绘制高度, 与进度条本身的触摸区高度相互独立.
  static const height = 12.0;

  final List<double> values;

  /// 线条与填充色, 通常取主题色.
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(painter: _TrendPainter(values, color)),
      ),
    );
  }
}

class _TrendPainter extends CustomPainter {
  _TrendPainter(this.values, this.color);

  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2 || size.width <= 0 || size.height <= 0) {
      return;
    }
    final line = _buildLine(size);
    final fill = Path.from(line)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(fill, Paint()..color = color.withValues(alpha: 0.28));
    canvas.drawPath(
      line,
      Paint()
        ..color = color.withValues(alpha: 0.8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  /// 用中点二次贝塞尔连接相邻点, 折线不会显得太生硬.
  Path _buildLine(Size size) {
    final stepX = size.width / (values.length - 1);
    // 上下各留半个描边, 线条不会被裁掉.
    final usable = size.height - 1;
    double yAt(int index) => size.height - values[index] * usable - 0.5;
    var lastX = 0.0;
    var lastY = yAt(0);
    final path = Path()..moveTo(lastX, lastY);
    for (var i = 1; i < values.length; i++) {
      final x = stepX * i;
      final y = yAt(i);
      path.quadraticBezierTo(lastX, lastY, (lastX + x) / 2, (lastY + y) / 2);
      lastX = x;
      lastY = y;
    }
    // 最后一段把曲线拉回右端, 终点正是最后一个密度点.
    path.quadraticBezierTo(lastX, lastY, size.width, lastY);
    return path;
  }

  /// 密度序列每次重算都是新对象, 用引用比较就够.
  @override
  bool shouldRepaint(_TrendPainter oldDelegate) =>
      oldDelegate.color != color || !identical(oldDelegate.values, values);
}
