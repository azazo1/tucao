import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:tucao/common/widgets/cc/comic_speech_bubble.dart';
import 'package:tucao/utils/logger.dart';

double _unit(double value) => value.clamp(0.0, 1.0).toDouble();

/// 贴着屏幕右边探出半身的感谢, 只由广告路由返回事件创建.
/// 不使用全局 Overlay, 离开所属页面时不会残留在其他页面上.
class CcPeekThanks extends StatefulWidget {
  const CcPeekThanks({super.key, required this.onDismiss});

  final VoidCallback onDismiss;

  static const spriteAsset = 'assets/images/cc/peek-sprite.webp';
  static const stillAsset = 'assets/images/cc/peek-still.webp';
  static const duration = Duration(milliseconds: 4400);
  static const frameDurations = [200, 250, 300, 350, 1200, 1200, 350, 300, 250];

  static int frameAt(Duration elapsed) {
    var end = 0;
    for (var frame = 0; frame < frameDurations.length; frame++) {
      end += frameDurations[frame];
      if (elapsed.inMilliseconds < end) return frame;
    }
    return frameDurations.length - 1;
  }

  @override
  State<CcPeekThanks> createState() => _CcPeekThanksState();
}

class _CcPeekThanksState extends State<CcPeekThanks>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: CcPeekThanks.duration,
  )..addStatusListener(_onStatus);
  ImageStream? _stream;
  ImageInfo? _image;
  late final ImageStreamListener _listener = ImageStreamListener(
    _onImage,
    onError: (Object error, StackTrace? stackTrace) {
      Log.e('CC 娘扶边图集加载失败, 使用静态图',
          error: error, stackTrace: stackTrace);
      if (mounted) {
        setState(() => _loadFailed = true);
        _start();
      }
    },
  );
  bool _reduceMotion = false;
  bool _accessible = false;
  bool _loadFailed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    _accessible = MediaQuery.accessibleNavigationOf(context);
    if (!_reduceMotion && _stream == null) {
      _stream = const AssetImage(CcPeekThanks.spriteAsset).resolve(
        createLocalImageConfiguration(context),
      );
      _stream!.addListener(_listener);
    }
    if (_reduceMotion || _image != null) _start();
  }

  void _onImage(ImageInfo image, bool synchronousCall) {
    if (!mounted) {
      image.dispose();
      return;
    }
    final previous = _image;
    setState(() => _image = image);
    previous?.dispose();
    _start();
  }

  void _start() {
    if (!_controller.isAnimating && !_controller.isCompleted) {
      _controller.forward();
    }
  }

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && !_accessible) {
      widget.onDismiss();
    }
  }

  @override
  void dispose() {
    _stream?.removeListener(_listener);
    _image?.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // 加载图集时保持隐藏, 避免先闪出完整半身, 再跳回探头第一帧.
    if (!_reduceMotion && !_loadFailed && _image == null) {
      return const SizedBox.shrink();
    }
    return SafeArea(
      top: false,
      // 人物必须贴住右侧边界, 底部仍避开系统手势区.
      right: false,
      child: Align(
        alignment: Alignment.bottomRight,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 340),
            child: Semantics(
              liveRegion: true,
              button: true,
              label: 'CC 娘: 谢谢你帮小站续命. 点击收起感谢',
              onTap: widget.onDismiss,
              child: ExcludeSemantics(
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (context, child) {
                    final t = _controller.value;
                    final elapsed = Duration(
                      milliseconds: (t * CcPeekThanks.duration.inMilliseconds).round(),
                    );
                    final frame = _accessible && t > 0.68
                        ? 4 : CcPeekThanks.frameAt(elapsed);
                    final stillMode = _reduceMotion || _loadFailed;
                    final bubbleOpacity = stillMode ? 1.0 :
                        _unit((t - 0.2) / 0.05) *
                        (_accessible ? 1.0 : _unit((0.8 - t) / 0.05));
                    final visibility = stillMode || _accessible ? 1.0 :
                        _unit(t / 0.025) * _unit((1 - t) / 0.04);
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: IgnorePointer(
                            ignoring: bubbleOpacity == 0,
                            child: Opacity(
                              opacity: bubbleOpacity,
                              child: GestureDetector(
                                onTap: widget.onDismiss,
                                child: ComicSpeechBubble(
                                  tail: ComicBubbleTail.right,
                                  fill: scheme.surfaceContainerLow,
                                  ink: scheme.outlineVariant,
                                  child: Text(
                                    '谢谢你帮\n小站续命~',
                                    textAlign: TextAlign.center,
                                    style: Theme.of(context).textTheme.bodyMedium,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        // 探头与收回都来自九帧动作, 不平移整张半身立绘.
                        ClipRect(
                          child: SizedBox(
                            width: 148,
                            height: 232,
                            child: Opacity(
                              opacity: visibility,
                              child: GestureDetector(
                                onTap: widget.onDismiss,
                                child: stillMode
                                    ? Image.asset(
                                        CcPeekThanks.stillAsset,
                                        fit: BoxFit.fill,
                                        errorBuilder: (_, error, stack) =>
                                            const SizedBox.shrink(),
                                      )
                                    : CustomPaint(
                                        painter: _PeekPainter(
                                          image: _image!.image,
                                          frame: frame,
                                        ),
                                      ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PeekPainter extends CustomPainter {
  const _PeekPainter({required this.image, required this.frame});

  final ui.Image image;
  final int frame;

  @override
  void paint(Canvas canvas, Size size) {
    final width = image.width / 3;
    final height = image.height / 3;
    canvas.drawImageRect(
      image,
      Rect.fromLTWH((frame % 3) * width, (frame ~/ 3) * height, width, height),
      Offset.zero & size,
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  @override
  bool shouldRepaint(_PeekPainter oldDelegate) =>
      image != oldDelegate.image || frame != oldDelegate.frame;
}
