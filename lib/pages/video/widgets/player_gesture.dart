import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:tucao/plugin/player/player_controller.dart';

/// 横向拖动的预览回调.
///
/// [preview] 是拖动中的目标位置, 松手与取消时为空值.
/// [committed] 为真表示松手时已经提交跳转, 界面可以保持在目标位置,
/// 等播放器上报新进度再交还真实进度.
typedef SeekPreviewCallback =
    void Function(Duration? preview, {required bool committed});

/// 播放器手势层.
///
/// 参照常见播放器的交互:
/// - 横向拖动调整进度, 拖动中通过 [onSeekPreview] 上报预览位置, 松手生效,
///   拖动到顶部左右角可取消.
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
    this.onSeekPreview,
  });

  final PlayerPageController controller;

  /// 单击时通知外层切换控制条.
  final VoidCallback onToggleControls;

  /// 横向拖动的预览位置.
  ///
  /// 外层用它让进度条游标跟随手指, 而不是等松手后才跳动.
  final SeekPreviewCallback? onSeekPreview;

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

  /// 拖满屏幕宽度对应的进度变化量上限.
  static const _seekSpan = Duration(seconds: 90);

  /// 竖向拖满屏幕高度对应的音量变化量.
  static const _volumeScreenRatio = 1.0;

  double _startX = 0;
  double _startY = 0;
  double _startLocalX = 0;
  bool _seekCancelling = false;

  /// 手势开始时播放器的进度, 用于累加拖动偏移.
  Duration _startPosition = Duration.zero;

  Duration? _seekTarget;

  double? _volumeTarget;

  /// 手势开始时的音量, 用作累加基准.
  double _startVolume = 100;

  /// 是否处于长按加速中, 用来在结束时恢复.
  bool _longPressing = false;

  /// 记录长按前的倍速.
  double _speedBeforeLongPress = 1;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      dragStartBehavior: DragStartBehavior.down,
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
    _startLocalX = details.localPosition.dx;
    _seekCancelling = false;
    _seekTarget = null;
    _volumeTarget = null;
    _startPosition = widget.controller.player.position;
    _startVolume = widget.controller.player.volume;
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
    final size = context.size ?? const Size(1, 1);
    final width = size.width;
    final localX = details.localPosition.dx.clamp(0.0, width);
    final localY = details.localPosition.dy.clamp(0.0, size.height);
    final cornerWidth = math.min(width * 0.25, 120.0);
    final cornerHeight = math.min(size.height / 3, 72.0);
    final cancelling =
        localY <= cornerHeight &&
        (localX <= cornerWidth || localX >= width - cornerWidth);
    // 拖满屏幕宽度最多改变 90 秒进度, 视频更短时以整段时长为跨度,
    // 避免小屏上轻微滑动就跳过很长一段.
    final span = math.min(_seekSpan.inMilliseconds, total.inMilliseconds);
    final ratio = dx / width;
    final targetMs = _startPosition.inMilliseconds + span * ratio;
    final clamped = targetMs.clamp(0, total.inMilliseconds);
    setState(() {
      _seekCancelling = cancelling;
      _seekTarget = Duration(milliseconds: clamped.toInt());
    });
    widget.onSeekPreview?.call(_seekTarget, committed: false);
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    final target = _seekTarget;
    // 落在取消区时不提交跳转, 界面也回到真实进度.
    final committed = target != null && !_seekCancelling;
    if (committed) {
      widget.controller.seek(target);
    }
    _onDragCancel(committed: committed);
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    final dy = details.globalPosition.dy - _startY;
    if (dy.abs() < _volumeThreshold && _volumeTarget == null) {
      return;
    }
    final width = context.size?.width ?? 1;
    // 竖向手势只作用于屏幕左半侧, 右半侧留给亮度等后续扩展.
    if (_startLocalX > width / 2) {
      return;
    }
    final height = context.size?.height ?? 1;
    final ratio = -dy / (height * _volumeScreenRatio);
    final value = (_startVolume + ratio * 100).clamp(0.0, 100.0);
    setState(() => _volumeTarget = value);
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    final target = _volumeTarget;
    if (target != null) {
      widget.controller.setVolume(target);
    }
    _onDragCancel();
  }

  /// 收尾清理. [committed] 表示本次横向拖动已经提交跳转.
  void _onDragCancel({bool committed = false}) {
    // 只有横向拖动会产生预览, 通知外层收起跟随状态.
    final hadPreview = _seekTarget != null;
    setState(() {
      _seekCancelling = false;
      _seekTarget = null;
      _volumeTarget = null;
      _startX = 0;
      _startY = 0;
      _startLocalX = 0;
      _startPosition = Duration.zero;
      _startVolume = 100;
    });
    if (hadPreview) {
      widget.onSeekPreview?.call(null, committed: committed);
    }
  }

  /// 手势提示, 没有手势时返回透明占位.
  Widget _buildIndicator(BuildContext context) {
    final text = _indicatorText();
    if (text == null) {
      return const SizedBox.expand();
    }
    return Center(
      child: DecoratedBox(
        key: _seekCancelling ? const ValueKey('seek-cancel-indicator') : null,
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
    if (_seekCancelling) {
      return '取消拖动';
    }
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
