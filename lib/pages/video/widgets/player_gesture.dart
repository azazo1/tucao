import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tucao/plugin/player/player_brightness.dart';
import 'package:tucao/plugin/player/player_controller.dart';
import 'package:tucao/plugin/player/player_speeds.dart';

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
/// - 左半侧竖向拖动调整画面亮度, 右半侧调整音量.
/// - 长按临时切换到 [PlayerGestureDetector.longPressSpeed], 松手恢复原速.
/// - 单击抬手立刻切换控制条. 双击播放暂停, 并撤回第一下的切换;
///   开启 [PlayerGestureDetector.doubleTapSeek] 后, 双击左右两侧改为快退快进
///   10 秒, 只有中间仍是播放暂停.
///
/// 手势层本身不绘制画面, 只在自己上面覆盖提示信息.
class PlayerGestureDetector extends StatefulWidget {
  const PlayerGestureDetector({
    super.key,
    required this.controller,
    required this.onToggleControls,
    this.onSeekPreview,
    this.longPressSpeed = PlayerSpeeds.defaultLongPress,
    this.doubleTapSeek = false,
    this.brightness,
    this.fullscreen = false,
  });

  final PlayerPageController controller;

  /// 是否处于全屏.
  ///
  /// 全屏时系统栏被隐藏, 从屏幕边缘下滑是系统呼出状态栏与导航栏的手势,
  /// 这时不把边缘的拖动当成亮度与音量调节.
  final bool fullscreen;

  /// 左半侧竖滑调节的画面亮度, 为空时左半侧不响应竖滑.
  final PlayerBrightness? brightness;

  /// 双击左右两侧是否快退快进, 由设置决定, 关闭时整个画面双击都是播放暂停.
  final bool doubleTapSeek;

  /// 长按切到的倍速, 由设置决定.
  final double longPressSpeed;

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

  /// 拖满屏幕宽度对应的进度变化量上限.
  static const _seekSpan = Duration(seconds: 90);

  /// 竖向拖满屏幕高度对应的音量变化量.
  static const _volumeScreenRatio = 1.0;

  /// 全屏时让给系统手势的边缘宽度.
  ///
  /// 全屏用的是沉浸模式, 状态栏与导航栏都藏起来了, 手指从屏幕边缘下滑是
  /// 系统呼出它们的手势. 这个范围内的拖动不调亮度与音量, 与 piliplus 的
  /// 做法一致 (它在 PointerDown 时用 25 逻辑像素屏蔽四边的手势).
  static const _edgeGuard = 25.0;

  /// 本次拖动起点落在屏幕边缘, 不处理任何拖动.
  bool _dragIgnored = false;

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

  /// 最近一次读到或设置的亮度, 作为下一次竖滑的起点.
  double _brightness = 0.5;

  /// 手势开始时的亮度.
  double _startBrightness = 0.5;

  double? _brightnessTarget;

  @override
  void initState() {
    super.initState();
    unawaited(_syncBrightness());
  }

  /// 进入播放页时读一次当前亮度, 第一次竖滑就从真实亮度开始变化.
  Future<void> _syncBrightness() async {
    final value = await widget.brightness?.current();
    if (value != null && mounted) {
      _brightness = value;
    }
  }

  /// 是否处于长按加速中, 用来在结束时恢复.
  bool _longPressing = false;

  /// 记录长按前的倍速.
  double _speedBeforeLongPress = 1;

  /// 双击时左右两侧用来快退快进的宽度比例.
  static const _doubleTapSide = 0.3;

  /// 双击一次跳过的时长.
  static const _doubleTapStep = Duration(seconds: 10);

  /// 双击跳转提示停留的时长.
  static const _doubleTapHintDuration = Duration(milliseconds: 800);

  /// 上一次单击抬起的位置, 在 [_tapWindow] 内再次点到附近算双击.
  Offset? _lastTapAt;

  /// 等待第二下点击的窗口, 到期后单击就不再能组成双击.
  Timer? _tapWindow;

  /// 这一串双击累计跳过的时长, 为零表示不显示提示.
  Duration _doubleTapTotal = Duration.zero;

  Timer? _doubleTapHintTimer;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      dragStartBehavior: DragStartBehavior.down,
      // 不用 onDoubleTap: 注册双击后手势竞技场会让双击与拖动, 长按互相等待.
      // 这里单击与双击自己判断, 单击等双击窗口结束才切换控制条.
      onTapUp: _onTapUp,
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

  /// 单击等双击窗口 [kDoubleTapTimeout] 结束才切换控制条;
  /// 窗口内在附近再点一次按双击处理, 不切换控制条.
  void _onTapUp(TapUpDetails details) {
    final at = details.localPosition;
    final last = _lastTapAt;
    final pending = _tapWindow?.isActive ?? false;
    _tapWindow?.cancel();
    if (pending && last != null && (at - last).distance <= kDoubleTapSlop) {
      _lastTapAt = null;
      _onDoubleTap(at.dx);
      return;
    }
    // 上一下点在别处, 不组成双击, 先把它当单击补上.
    if (pending) {
      widget.onToggleControls();
    }
    _lastTapAt = at;
    _tapWindow = Timer(kDoubleTapTimeout, () {
      _lastTapAt = null;
      if (mounted) {
        widget.onToggleControls();
      }
    });
  }

  /// 双击位置: 开启快退快进时左右两侧各占 [_doubleTapSide] 宽度用来跳转,
  /// 其余位置以及关闭时都是播放暂停.
  void _onDoubleTap(double x) {
    final width = context.size?.width ?? 1;
    final player = widget.controller.player;
    final total = player.duration;
    final seekable = widget.doubleTapSeek;
    final forward = seekable && x >= width * (1 - _doubleTapSide);
    final backward = seekable && x <= width * _doubleTapSide;
    if ((!forward && !backward) || total <= Duration.zero) {
      widget.controller.togglePlay();
      return;
    }
    final step = forward ? _doubleTapStep : -_doubleTapStep;
    unawaited(HapticFeedback.lightImpact());
    final targetMs = (player.position + step).inMilliseconds.clamp(
      0,
      total.inMilliseconds,
    );
    widget.controller.seek(Duration(milliseconds: targetMs));
    // 连续双击同一侧时累加提示的秒数, 换了方向重新计.
    _doubleTapHintTimer?.cancel();
    setState(() {
      final sameSide = _doubleTapTotal.isNegative == step.isNegative;
      _doubleTapTotal = sameSide ? _doubleTapTotal + step : step;
    });
    _doubleTapHintTimer = Timer(_doubleTapHintDuration, () {
      if (mounted) {
        setState(() => _doubleTapTotal = Duration.zero);
      }
    });
  }

  @override
  void dispose() {
    _tapWindow?.cancel();
    _doubleTapHintTimer?.cancel();
    super.dispose();
  }

  void _onLongPressStart(LongPressStartDetails details) {
    final player = widget.controller.player;
    _speedBeforeLongPress = player.speed;
    _longPressing = true;
    // 倍速是看不见的状态变化, 震一下让人知道已经生效.
    unawaited(HapticFeedback.mediumImpact());
    widget.controller.setSpeed(widget.longPressSpeed);
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

  /// 全屏时屏幕四边的拖动留给系统手势, 其余位置照常调亮度与音量.
  bool _isDragStartAllowed(Offset local) {
    final size = context.size;
    if (size == null || size.isEmpty) {
      return true;
    }
    return local.dx >= _edgeGuard &&
        local.dy >= _edgeGuard &&
        local.dx <= size.width - _edgeGuard &&
        local.dy <= size.height - _edgeGuard;
  }

  void _onDragStart(DragStartDetails details) {
    // dragStartBehavior 是 down, localPosition 就是手指按下的位置.
    _dragIgnored =
        widget.fullscreen && !_isDragStartAllowed(details.localPosition);
    _startX = details.globalPosition.dx;
    _startY = details.globalPosition.dy;
    _startLocalX = details.localPosition.dx;
    _seekCancelling = false;
    _seekTarget = null;
    _volumeTarget = null;
    _startPosition = widget.controller.player.position;
    _startVolume = widget.controller.player.volume;
    _startBrightness = _brightness;
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    if (_dragIgnored) {
      return;
    }
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
    // 进出取消区时提示一下, 不用盯着角落也知道松手会不会跳转.
    if (cancelling != _seekCancelling && _seekTarget != null) {
      unawaited(HapticFeedback.selectionClick());
    }
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
    if (_dragIgnored) {
      return;
    }
    final dy = details.globalPosition.dy - _startY;
    if (dy.abs() < _volumeThreshold &&
        _volumeTarget == null &&
        _brightnessTarget == null) {
      return;
    }
    final width = context.size?.width ?? 1;
    final height = context.size?.height ?? 1;
    final ratio = -dy / (height * _volumeScreenRatio);
    if (_startLocalX < width / 2) {
      final brightness = widget.brightness;
      if (brightness == null) {
        return;
      }
      // 亮度跟手实时生效, 松手不再额外提交.
      final value = (_startBrightness + ratio).clamp(0.0, 1.0);
      _brightness = value;
      unawaited(brightness.set(value));
      setState(() => _brightnessTarget = value);
      return;
    }
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
      _dragIgnored = false;
      _seekCancelling = false;
      _seekTarget = null;
      _volumeTarget = null;
      _brightnessTarget = null;
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
    if (_brightnessTarget != null) {
      return '亮度 ${(_brightnessTarget! * 100).round()}%';
    }
    if (_longPressing) {
      return '${PlayerSpeeds.label(widget.longPressSpeed)} 播放中';
    }
    if (_doubleTapTotal != Duration.zero) {
      final seconds = _doubleTapTotal.inSeconds;
      return seconds > 0 ? '快进 $seconds 秒' : '快退 ${-seconds} 秒';
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
