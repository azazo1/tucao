import 'package:flutter/material.dart';

/// 播放器控制条的显隐动画: 淡入淡出, 同时沿 [slideFrom] 方向滑入滑出.
///
/// 动画结束后隐藏的子树直接卸载, 与原来直接移除的效果一致,
/// 淡出过程中也不再响应点击, 避免点到正在消失的按钮.
class PlayerControlsFade extends StatefulWidget {
  const PlayerControlsFade({
    super.key,
    required this.visible,
    required this.child,
    this.slideFrom = Offset.zero,
  });

  final bool visible;

  /// 隐藏时相对自身尺寸的偏移, 比如顶栏用 `Offset(0, -0.3)`.
  final Offset slideFrom;

  final Widget child;

  static const duration = Duration(milliseconds: 200);

  /// 确保动画走完并卸载子树的等待时长. 动画正好走满 [duration] 时状态还没切到结束,
  /// 需要再多等一帧.
  static const settleDuration = Duration(milliseconds: 250);

  @override
  State<PlayerControlsFade> createState() => _PlayerControlsFadeState();
}

class _PlayerControlsFadeState extends State<PlayerControlsFade>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation = AnimationController(
    vsync: this,
    duration: PlayerControlsFade.duration,
    value: widget.visible ? 1 : 0,
  );

  late final Animation<double> _curve = CurvedAnimation(
    parent: _animation,
    curve: Curves.easeOut,
    reverseCurve: Curves.easeIn,
  );

  @override
  void initState() {
    super.initState();
    _animation.addStatusListener((_) => setState(() {}));
  }

  @override
  void didUpdateWidget(covariant PlayerControlsFade oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible != oldWidget.visible) {
      if (widget.visible) {
        _animation.forward();
      } else {
        _animation.reverse();
      }
    }
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_animation.isDismissed) {
      return const SizedBox.shrink();
    }
    return IgnorePointer(
      ignoring: !widget.visible,
      child: FadeTransition(
        opacity: _curve,
        child: SlideTransition(
          position: Tween(
            begin: widget.slideFrom,
            end: Offset.zero,
          ).animate(_curve),
          child: widget.child,
        ),
      ),
    );
  }
}
