import 'package:flutter/material.dart';
import 'package:tucao/plugin/player/player_controller.dart';

/// 播放器手势层.
///
/// 参照常见播放器的交互:
/// - 横向拖动调整进度, 松手生效, 拖动过程中显示目标时间.
/// - 竖向拖动调整音量, 只作用于屏幕左半侧.
/// - 长按临时切换到 3 倍速, 松手恢复原速.
/// - 单击切换控制条, 双击播放暂停.
///
/// 手势层本身不绘制画面, 只在自己上面覆盖提示信息.
class PlayerGestureDetector extends StatefulWidget {
  const PlayerGestureDetector({
    super.key,
    required this.controller,
    required this.onToggleControls,
  });

  final PlayerPageController controller;

  /// 单击时通知外层切换控制条.
  final VoidCallback onToggleControls;

  @override
  State<PlayerGestureDetector> createState() => _PlayerGestureDetectorState();
}

class _PlayerGestureDetectorState extends State<PlayerGestureDetector> {
  /// 横向拖动超过这个距离才认为是在调整进度.
  static const _seekThreshold = 12.0;

  /// 竖向拖动超过这个距离才认为是在调整音量.
  static const _volumeThreshold = 12.0;

  /// 长按切到的倍速.
  static const _longPressSpeed = 3.0;

  /// 拖满屏幕宽度对应的进度变化量, 取屏幕宽度的 1.2 倍作为基准时长.
  static const _seekScreenRatio = 1.2;

  /// 竖向拖满屏幕高度对应的音量变化量.
  static const _volumeScreenRatio = 1.0;

  double _startX = 0;
  double _startY = 0;

  /// 手势开始时播放器的进度, 用于累加拖动偏移.
  Duration _startPosition = Duration.zero;

  Duration? _seekTarget;

  double? _volumeTarget;

  /// 是否处于长按加速中, 用来在结束时恢复.
  bool _longPressing = false;

  /// 记录长按前的倍速.
  double _speedBeforeLongPress = 1;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onToggleControls,
      onDoubleTap: widget.controller.togglePlay,
      onLongPressStart: _onLongPressStart,
      onLongPressEnd: _onLongPressEnd,
      onLongPressCancel: _onLongPressEnd,
      onHorizontalDragStart: _onDragStart,
      onHorizontalDragUpdate: _onHorizontalDragUpdate,
      onHorizontalDragEnd: _onHorizontalDragEnd,
      onHorizontalDragCancel: _onDragCancel,
      onVerticalDragStart: _onDragStart,
      onVerticalDragUpdate: _onVerticalDragUpdate,
      onVerticalDragEnd: _onVerticalDragEnd,
      onVerticalDragCancel: _onDragCancel,
      child: _buildIndicator(context),
    );
  }

  void _onLongPressStart(LongPressStartDetails details) {
    final player = widget.controller.player;
    _speedBeforeLongPress = player.speed;
    _longPressing = true;
    widget.controller.setSpeed(_longPressSpeed);
    setState(() {});
  }

  void _onLongPressEnd([dynamic details]) {
    if (!_longPressing) {
      return;
    }
    _longPressing = false;
    widget.controller.setSpeed(_speedBeforeLongPress);
    setState(() {});
  }

  void _onDragStart(DragStartDetails details) {
    _startX = details.globalPosition.dx;
    _startY = details.globalPosition.dy;
    _startPosition = widget.controller.player.position;
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    final total = widget.controller.player.duration;
    if (total <= Duration.zero) {
      return;
    }
    final dx = details.globalPosition.dx - _startX;
    if (dx.abs() < _seekThreshold && _seekTarget == null) {
      return;
    }
    final width = context.size?.width ?? 1;
    // 以屏幕宽度的 1.2 倍代表整段时长, 便于在小屏上快速定位.
    final ratio = dx / (width * _seekScreenRatio);
    final targetMs =
        _startPosition.inMilliseconds + (total.inMilliseconds * ratio);
    final clamped = targetMs.clamp(0, total.inMilliseconds);
    setState(() => _seekTarget = Duration(milliseconds: clamped.toInt()));
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    final target = _seekTarget;
    if (target == null) {
      return;
    }
    widget.controller.seek(target);
    setState(() => _seekTarget = null);
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    final dy = details.globalPosition.dy - _startY;
    if (dy.abs() < _volumeThreshold && _volumeTarget == null) {
      return;
    }
    final width = context.size?.width ?? 1;
    // 竖向手势只作用于屏幕左半侧, 右半侧留给亮度等后续扩展.
    if (_startX > width / 2) {
      return;
    }
    final height = context.size?.height ?? 1;
    final start = _volumeTarget ?? widget.controller.player.volume;
    final ratio = -dy / (height * _volumeScreenRatio);
    final value = (start + ratio * 100).clamp(0.0, 100.0);
    setState(() => _volumeTarget = value);
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    final target = _volumeTarget;
    if (target == null) {
      return;
    }
    widget.controller.setVolume(target);
    setState(() => _volumeTarget = null);
  }

  void _onDragCancel() {
    setState(() {
      _seekTarget = null;
      _volumeTarget = null;
    });
  }

  /// 手势提示, 没有手势时返回透明占位.
  Widget _buildIndicator(BuildContext context) {
    final text = _indicatorText();
    if (text == null) {
      return const SizedBox.expand();
    }
    return Center(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  String? _indicatorText() {
    if (_seekTarget != null) {
      final target = _seekTarget!;
      final total = widget.controller.player.duration;
      return '${_format(target)} / ${_format(total)}';
    }
    if (_volumeTarget != null) {
      return '音量 ${_volumeTarget!.round()}%';
    }
    if (_longPressing) {
      return '${_longPressSpeed.toStringAsFixed(0)}x 播放中';
    }
    return null;
  }

  static String _format(Duration value) {
    final total = value.inSeconds;
    final minutes = total ~/ 60;
    final seconds = total % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}
