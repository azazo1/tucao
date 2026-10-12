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
import 'package:tucao/utils/site_links.dart';
import 'package:tucao/utils/utils.dart';

/// 播放器区域: 视频画面, 弹幕层与控制条.
///
/// 控制条与进度条直接读 [PlayerPageController.player] 的状态,
/// 因此这里不重复保存播放状态.
class VideoPlayerView extends StatefulWidget {
  const VideoPlayerView({
    super.key,
    required this.controller,
    required this.fullscreen,
    required this.onToggleFullscreen,
    required this.onOpenWebsite,
  });

  final PlayerPageController controller;

  /// 是否处于全屏, 布局由外层决定.
  final bool fullscreen;

  final VoidCallback onToggleFullscreen;
  final VoidCallback onOpenWebsite;

  @override
  State<VideoPlayerView> createState() => _VideoPlayerViewState();
}

class _VideoPlayerViewState extends State<VideoPlayerView> {
  /// 全屏时控制条会自动隐藏, 竖屏下常驻.
  static const _hideDelay = Duration(seconds: 4);

  static const _speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

  bool _showControls = true;
  bool _settingsOpen = false;

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
    if (oldWidget.fullscreen != widget.fullscreen) {
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
    if (!widget.fullscreen || _settingsOpen) {
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

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: Colors.black),
        _buildVideo(),
        DanmakuScreen<DanmakuModel>(
          key: const ValueKey('danmaku'),
          createdController: _controller.attachDanmaku,
          option: _controller.danmakuOption,
        ),
        Positioned.fill(
          child: PlayerGestureDetector(
            controller: _controller,
            onToggleControls: _toggleControls,
          ),
        ),
        if (_showControls) _buildControls(context),
        if (widget.fullscreen && _showControls) _buildFullscreenBack(),
        _buildBuffering(),
        _buildSourceTip(),
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

  Widget _buildButtonRow() {
    final player = _controller.player;
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
        const Spacer(),
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
      await showDanmakuSettingsSheet(context, onChanged: (preferences) {
        if (mounted && identical(controller, _controller) && _settingsOpen) {
          controller.applyDanmakuPreferences(preferences);
        }
      });
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
class PlayerProgressBar extends StatefulWidget {
  const PlayerProgressBar({
    super.key,
    required this.position,
    required this.duration,
    required this.buffered,
    required this.onSeek,
  });

  final Duration position;
  final Duration duration;
  final Duration buffered;

  /// 拖动结束时提交跳转.
  final ValueChanged<Duration> onSeek;

  @override
  State<PlayerProgressBar> createState() => _PlayerProgressBarState();
}

class _PlayerProgressBarState extends State<PlayerProgressBar> {
  static const _trackHeight = 3.0;
  static const _thumbSize = 11.0;
  static const _touchHeight = 24.0;

  /// 拖动过程中的预览位置, 为空表示没有在拖动.
  double? _dragging;

  double get _totalSeconds => widget.duration.inMilliseconds / 1000;

  double get _positionSeconds =>
      _dragging ?? widget.position.inMilliseconds / 1000;

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
    setState(() => _dragging = null);
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
                      width: _thumbSize,
                      height: _thumbSize,
                      decoration: BoxDecoration(
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
