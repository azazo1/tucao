import 'dart:async';

import 'package:canvas_danmaku/canvas_danmaku.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:tucao/models/danmaku.dart';
import 'package:tucao/pages/video/widgets/danmaku_settings_sheet.dart';
import 'package:tucao/pages/video/widgets/player_gesture.dart';
import 'package:tucao/utils/danmaku_preferences_store.dart';
import 'package:tucao/plugin/player/player_controller.dart';
import 'package:tucao/services/cast/session.dart';
import 'package:tucao/utils/site_links.dart';
import 'package:tucao/utils/storage_pref.dart';
import 'package:tucao/utils/utils.dart';

/// 播放器区域: 视频画面, 弹幕层与控制条.
///
/// 控制条与进度条直接读 [PlayerPageController.player] 的状态,
/// 因此这里不重复保存播放状态. 投屏时整块换成电视遥控面板.
class VideoPlayerView extends StatefulWidget {
  const VideoPlayerView({
    super.key,
    required this.controller,
    required this.fullscreen,
    required this.onToggleFullscreen,
    required this.onOpenWebsite,
    this.pipMode = false,
    this.onEnterPip,
    this.cast,
    this.onExitCast,
  });

  final PlayerPageController controller;

  /// 是否处于全屏, 布局由外层决定.
  final bool fullscreen;

  /// 是否已经进入画中画小窗, 小窗里只保留画面.
  final bool pipMode;

  /// 进入画中画, 为空表示当前设备不支持, 不显示入口.
  final VoidCallback? onEnterPip;

  final VoidCallback onToggleFullscreen;
  final VoidCallback onOpenWebsite;

  /// 正在进行的投屏会话, 非空时播放器区域变成电视遥控.
  final CastSession? cast;

  /// 退出投屏.
  final VoidCallback? onExitCast;

  @override
  State<VideoPlayerView> createState() => _VideoPlayerViewState();
}

class _VideoPlayerViewState extends State<VideoPlayerView> {
  /// 全屏时控制条会自动隐藏, 竖屏下常驻.
  static const _hideDelay = Duration(seconds: 4);

  static const _speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

  bool _showControls = true;
  bool _settingsOpen = false;

  /// 手势横向拖动的预览位置, 非空时进度条游标跟随手指.
  Duration? _seekPreview;

  /// 手势松手时是否提交了跳转, 供进度条决定要不要保留目标位置.
  bool _seekCommitted = false;

  Timer? _hideTimer;

  PlayerPageController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _restartHideTimer();
  }

  @override
  void didUpdateWidget(covariant VideoPlayerView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fullscreen != widget.fullscreen ||
        oldWidget.pipMode != widget.pipMode) {
      _restartHideTimer();
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  void _restartHideTimer() {
    _hideTimer?.cancel();
    if (widget.pipMode || !widget.fullscreen || _settingsOpen) {
      return;
    }
    _hideTimer = Timer(_hideDelay, () {
      if (mounted) {
        setState(() => _showControls = false);
      }
    });
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls) {
      _restartHideTimer();
    }
  }

  void _keepControls() {
    if (!_showControls) {
      setState(() => _showControls = true);
    }
    _restartHideTimer();
  }

  /// 手势拖动期间保持控制条可见, 让进度条游标跟着手指走.
  ///
  /// 松手提交跳转时把目标位置保留给进度条, 等播放器上报新位置再交还;
  /// 落在取消区时不保留, 游标直接回到真实进度.
  void _onSeekPreview(Duration? preview, {required bool committed}) {
    if (preview != null) {
      _hideTimer?.cancel();
    } else {
      _restartHideTimer();
    }
    setState(() {
      if (preview != null) {
        _showControls = true;
      }
      _seekPreview = preview;
      _seekCommitted = committed;
    });
  }

  @override
  Widget build(BuildContext context) {
    // 小窗里系统只给一小块画面, 控制条与弹幕都收起来.
    final inPip = widget.pipMode;
    final cast = widget.cast;
    final casting = cast != null;
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: Colors.black),
        _buildVideo(),
        // 小窗里只留画面, 投屏时画面在电视上, 弹幕也没有意义.
        Offstage(
          offstage: inPip || casting,
          child: DanmakuScreen<DanmakuModel>(
            key: const ValueKey('danmaku'),
            createdController: _controller.attachDanmaku,
            option: _controller.danmakuOption,
          ),
        ),
        if (!casting)
          Positioned.fill(
            child: PlayerGestureDetector(
              controller: _controller,
              onToggleControls: _toggleControls,
              onSeekPreview: _onSeekPreview,
            ),
          ),
        if (!casting && _showControls && !inPip) _buildControls(context),
        if (!casting) _buildBuffering(),
        if (!casting) _buildSourceTip(),
        if (casting && !inPip) _buildCastControls(context, cast),
        // 返回按钮放在遥控面板之上, 全屏时也能退出全屏.
        if (widget.fullscreen &&
            !inPip &&
            (casting || _showControls))
          _buildFullscreenBack(),
      ],
    );
  }

  /// 全屏返回按钮随控制条一起显隐, 点击画面可重新显示.
  Widget _buildFullscreenBack() {
    return Positioned(
      left: 0,
      top: 0,
      child: SafeArea(
        child: IconButton(
          onPressed: widget.onToggleFullscreen,
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          tooltip: '退出全屏',
        ),
      ),
    );
  }

  Widget _buildVideo() {
    return Obx(() {
      if (!_controller.playerReady.value || !_controller.player.initialized) {
        return const SizedBox.shrink();
      }
      return Video(
        controller: _controller.player.videoController,
        controls: NoVideoControls,
        fit: BoxFit.contain,
        fill: Colors.black,
        // 息屏与后台行为由 TucaoPlayer 统一控制.
        wakelock: false,
        pauseUponEnteringBackgroundMode: false,
      );
    });
  }

  /// 源失效和真实播放错误复用覆盖层与浏览器备用按钮.
  Widget _buildSourceTip() {
    return ListenableBuilder(
      listenable: _controller.player,
      builder: (context, child) => Obx(() {
        final nativeError = _controller.playerReady.value
            ? _controller.player.error
            : null;
        final tip =
            _controller.sourceError.value ??
            (nativeError == null ? null : '播放失败: $nativeError');
        if (tip == null) {
          return const SizedBox.shrink();
        }
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                nativeError == null ? Icons.link_off : Icons.error_outline,
                color: Colors.white70,
                size: 32,
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  tip,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (SiteLinks.video(
                    _controller.hid,
                    part: _controller.part.value,
                  ) !=
                  null)
                TextButton.icon(
                  onPressed: widget.onOpenWebsite,
                  style: TextButton.styleFrom(foregroundColor: Colors.white),
                  icon: const Icon(Icons.open_in_browser, size: 18),
                  label: const Text('浏览器查看'),
                ),
            ],
          ),
        );
      }),
    );
  }

  Widget _buildBuffering() {
    final player = _controller.player;
    return ListenableBuilder(
      listenable: player,
      builder: (context, child) {
        final visible =
            player.buffering && !player.completed && player.error == null;
        return IgnorePointer(
          child: Center(
            child: visible
                ? const CircularProgressIndicator(strokeWidth: 2)
                : const SizedBox.shrink(),
          ),
        );
      },
    );
  }

  Widget _buildControls(BuildContext context) {
    return Positioned.fill(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: GestureDetector(
          onTap: _keepControls,
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.black54],
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 16, 10, 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [_buildProgressRow(), _buildButtonRow()],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 投屏时的遥控面板: 画面在电视上, 这里只留状态, 进度与按键.
  Widget _buildCastControls(BuildContext context, CastSession session) {
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {},
        child: Material(
          color: Colors.black,
          child: AnimatedBuilder(
            animation: session,
            builder: (context, _) {
              final playing = session.state == CastState.playing;
              final duration = session.duration;
              return SafeArea(
                child: Column(
                  children: [
                    Expanded(
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.cast_connected,
                              size: 40,
                              color: Colors.white54,
                            ),
                            const SizedBox(height: 12),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                              ),
                              child: Text(
                                session.device.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _castStateLabel(session),
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 2),
                            const Text(
                              '弹幕仅在手机上显示',
                              style: TextStyle(
                                color: Colors.white38,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Text(
                                Utils.formatDuration(session.position),
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: PlayerProgressBar(
                                  position: session.position,
                                  duration: duration,
                                  buffered: Duration.zero,
                                  onSeek: (position) =>
                                      unawaited(session.seek(position)),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                duration > Duration.zero
                                    ? Utils.formatDuration(duration)
                                    : '--:--',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              _castButton(
                                Icons.replay_10,
                                () => _seekCastBy(
                                  session,
                                  const Duration(seconds: -10),
                                ),
                                tooltip: '后退 10 秒',
                              ),
                              _castButton(
                                playing ? Icons.pause : Icons.play_arrow,
                                () => playing
                                    ? session.pause()
                                    : session.resume(),
                                size: 40,
                                tooltip: playing ? '暂停' : '继续',
                              ),
                              _castButton(
                                Icons.forward_10,
                                () => _seekCastBy(
                                  session,
                                  const Duration(seconds: 10),
                                ),
                                tooltip: '前进 10 秒',
                              ),
                              _castButton(
                                Icons.stop_circle_outlined,
                                () => widget.onExitCast?.call(),
                                size: 34,
                                tooltip: '退出投屏',
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  IconButton _castButton(
    IconData icon,
    VoidCallback onPressed, {
    String? tooltip,
    double size = 28,
  }) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, size: size, color: Colors.white),
    );
  }

  /// 遥控面板上的相对跳转, 结果夹在开头与片尾之间.
  void _seekCastBy(CastSession session, Duration delta) {
    final total = session.duration;
    final upper = total > Duration.zero
        ? total.inMilliseconds
        : session.position.inMilliseconds;
    final target = (session.position + delta).inMilliseconds.clamp(0, upper);
    unawaited(session.seek(Duration(milliseconds: target.toInt())));
  }

  String _castStateLabel(CastSession session) {
    return switch (session.state) {
      CastState.connecting => '正在连接…',
      CastState.playing => '正在播放',
      CastState.paused => '已暂停',
      CastState.failed => '投屏中断',
      _ => '已停止',
    };
  }

  Widget _buildProgressRow() {
    final player = _controller.player;
    return ListenableBuilder(
      listenable: player,
      builder: (context, child) {
        return Row(
          children: [
            Text(
              Utils.formatDuration(player.position),
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: PlayerProgressBar(
                position: player.position,
                duration: player.duration,
                buffered: player.buffered,
                preview: _seekPreview,
                previewCommitted: _seekCommitted,
                onSeek: _onSeek,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              Utils.formatDuration(player.duration),
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ],
        );
      },
    );
  }

  void _onSeek(Duration position) {
    _keepControls();
    _controller.seek(position);
  }

  /// 跳过片头片尾用的按钮, 一次前进 [Pref.playerSeekStep] 秒.
  ///
  /// 秒数在设置页可调, 按钮上不标出. 视频还没加载出时长时按钮照常显示,
  /// 此时点击以当前位置为上界, 不会产生跳转.
  Widget _buildSeekStepButton() {
    return _iconButton(
      Icons.fast_forward,
      () =>
          _seekBy(Duration(milliseconds: (Pref.playerSeekStep * 1000).round())),
    );
  }

  /// 相对当前位置跳转, 结果夹在开头与片尾之间.
  void _seekBy(Duration delta) {
    _keepControls();
    final player = _controller.player;
    final total = player.duration;
    final upper = total > Duration.zero
        ? total.inMilliseconds
        : player.position.inMilliseconds;
    final target = (player.position + delta).inMilliseconds.clamp(0, upper);
    _controller.seek(Duration(milliseconds: target.toInt()));
  }

  Widget _buildButtonRow() {
    final player = _controller.player;
    final onEnterPip = widget.onEnterPip;
    return Row(
      children: [
        ListenableBuilder(
          listenable: player,
          builder: (context, child) => _iconButton(
            player.playing ? Icons.pause : Icons.play_arrow,
            _controller.togglePlay,
            size: 26,
          ),
        ),
        _iconButton(Icons.replay_5, () => _seekBy(const Duration(seconds: -5))),
        _iconButton(Icons.forward_5, () => _seekBy(const Duration(seconds: 5))),
        _buildSeekStepButton(),
        const Spacer(),
        Obx(
          () => _iconButton(
            _controller.danmakuEnabled.value
                ? Icons.subtitles
                : Icons.subtitles_off,
            _controller.toggleDanmaku,
          ),
        ),
        Tooltip(
          message: '弹幕设置',
          child: _iconButton(Icons.tune, _openDanmakuSettings),
        ),
        _buildSpeedButton(),
        if (onEnterPip != null)
          Tooltip(
            message: '画中画',
            child: _iconButton(Icons.picture_in_picture_alt, onEnterPip),
          ),
        _iconButton(
          widget.fullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
          widget.onToggleFullscreen,
        ),
      ],
    );
  }

  Future<void> _openDanmakuSettings() async {
    if (_settingsOpen) return;
    final controller = _controller;
    _settingsOpen = true;
    _hideTimer?.cancel();
    try {
      await showDanmakuSettingsSheet(
        context,
        onChanged: (preferences) {
          if (mounted && identical(controller, _controller) && _settingsOpen) {
            controller.applyDanmakuPreferences(preferences);
          }
        },
      );
    } finally {
      if (mounted && identical(controller, _controller)) {
        // 只恢复当前 View 自己的 controller 数据, 不向被覆盖的路由发送界面反馈.
        controller.applyDanmakuPreferences(DanmakuPreferencesStore.read());
        _settingsOpen = false;
        _restartHideTimer();
      }
    }
  }

  Widget _iconButton(IconData icon, VoidCallback onTap, {double size = 20}) {
    return IconButton(
      onPressed: () {
        _keepControls();
        onTap();
      },
      icon: Icon(icon, color: Colors.white, size: size),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _buildSpeedButton() {
    final player = _controller.player;
    return ListenableBuilder(
      listenable: player,
      builder: (context, child) {
        final text =
            '${player.speed.toStringAsFixed(player.speed == player.speed.roundToDouble() ? 1 : 2)}x';
        return PopupMenuButton<double>(
          tooltip: '倍速',
          initialValue: player.speed,
          onOpened: _keepControls,
          onSelected: (value) {
            _keepControls();
            _controller.setSpeed(value);
          },
          itemBuilder: (context) => [
            for (final speed in _speeds)
              PopupMenuItem(value: speed, child: Text('${speed}x')),
          ],
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            child: Text(
              text,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
        );
      },
    );
  }
}

/// 播放进度条.
///
/// 自绘的原因是需要同时展示播放进度与缓冲进度, 并支持拖动时即时预览.
/// 预览有三个来源, 优先级从高到低: 直接拖动进度条, 手势层传入的
/// [preview], 以及提交跳转后等待播放位置追上的过渡值.
class PlayerProgressBar extends StatefulWidget {
  const PlayerProgressBar({
    super.key,
    required this.position,
    required this.duration,
    required this.buffered,
    required this.onSeek,
    this.preview,
    this.previewCommitted = false,
  });

  final Duration position;
  final Duration duration;
  final Duration buffered;

  /// 手势层横向拖动的预览位置, 非空时游标跟随手指.
  final Duration? preview;

  /// [preview] 结束时空值是否代表已经提交跳转.
  ///
  /// 提交后游标停在目标位置, 等播放位置追上来再交还真实进度,
  /// 避免松手瞬间游标先弹回原处再跳到目标.
  final bool previewCommitted;

  /// 拖动结束时提交跳转.
  final ValueChanged<Duration> onSeek;

  @override
  State<PlayerProgressBar> createState() => _PlayerProgressBarState();
}

class _PlayerProgressBarState extends State<PlayerProgressBar> {
  static const _trackHeight = 3.0;
  static const _thumbSize = 11.0;
  static const _touchHeight = 24.0;

  /// 直接拖动进度条时的预览位置, 为空表示没有在拖动.
  double? _dragging;

  /// 提交跳转后的过渡位置, 等播放位置更新再交还真实进度.
  double? _settle;

  /// 过渡开始时播放器的位置, 用来判断播放器是否已经响应跳转.
  Duration _settleFrom = Duration.zero;

  double get _totalSeconds => widget.duration.inMilliseconds / 1000;

  double get _positionSeconds =>
      _dragging ?? _previewSeconds ?? widget.position.inMilliseconds / 1000;

  /// 手势层预览优先, 松手后沿用最后的目标位置直到播放器响应.
  double? get _previewSeconds {
    final preview = widget.preview;
    if (preview != null) {
      return preview.inMilliseconds / 1000;
    }
    return _settle;
  }

  @override
  void didUpdateWidget(covariant PlayerProgressBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.preview != null) {
      // 新一轮拖动开始, 丢弃上一次的过渡.
      _settle = null;
      return;
    }
    if (oldWidget.preview != null) {
      // 松手提交跳转时保留目标位置, 取消拖动时直接回到真实进度.
      if (widget.previewCommitted) {
        _startSettle(oldWidget.preview!.inMilliseconds / 1000);
      } else {
        _settle = null;
      }
      return;
    }
    // 播放器上报了新位置, 说明跳转已经生效, 交还真实进度.
    if (_settle != null && widget.position != _settleFrom) {
      _settle = null;
    }
  }

  void _startSettle(double value) {
    _settle = value;
    _settleFrom = widget.position;
  }

  double _ratio(double value) {
    final total = _totalSeconds;
    if (total <= 0) {
      return 0;
    }
    return (value / total).clamp(0, 1);
  }

  void _updateFromDx(double dx, double width) {
    if (width <= 0 || _totalSeconds <= 0) {
      return;
    }
    setState(() => _dragging = (dx / width).clamp(0, 1) * _totalSeconds);
  }

  void _commit() {
    final value = _dragging;
    if (value == null) {
      return;
    }
    setState(() {
      _dragging = null;
      _startSettle(value);
    });
    widget.onSeek(Duration(milliseconds: (value * 1000).round()));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) {
            _updateFromDx(details.localPosition.dx, width);
            _commit();
          },
          onHorizontalDragStart: (details) =>
              _updateFromDx(details.localPosition.dx, width),
          onHorizontalDragUpdate: (details) =>
              _updateFromDx(details.localPosition.dx, width),
          onHorizontalDragEnd: (_) => _commit(),
          onHorizontalDragCancel: _commit,
          child: SizedBox(
            height: _touchHeight,
            child: Center(
              child: Stack(
                alignment: Alignment.centerLeft,
                children: [
                  _bar(Colors.white24, 1),
                  _bar(
                    Colors.white70,
                    _ratio(widget.buffered.inMilliseconds / 1000),
                  ),
                  _bar(scheme.primary, _ratio(_positionSeconds)),
                  Align(
                    alignment: Alignment(_ratio(_positionSeconds) * 2 - 1, 0),
                    child: Container(
                      key: const ValueKey('player-progress-thumb'),
                      width: _thumbSize,
                      height: _thumbSize,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _bar(Color color, double ratio) {
    return Align(
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: ratio.clamp(0.0, 1.0),
        child: Container(
          height: _trackHeight,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(_trackHeight / 2),
          ),
        ),
      ),
    );
  }
}
