import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:tucao/utils/logger.dart';

/// 九宫格切帧动画. 只播放一轮, 使用图集以便暂停, 重播和减弱动画.
class CcThanksAnimation extends StatefulWidget {
  const CcThanksAnimation({super.key, this.replay = 0});

  final int replay;

  static const spriteAsset = 'assets/images/cc/thanks-sprite.webp';
  static const stillAsset = 'assets/images/cc/thanks-still.webp';
  static const frameDurations = [600, 180, 200, 420, 200, 300, 600, 220, 900];
  static const duration = Duration(milliseconds: 3620);

  static int frameAt(Duration elapsed) {
    var end = 0;
    for (var frame = 0; frame < frameDurations.length; frame++) {
      end += frameDurations[frame];
      if (elapsed.inMilliseconds < end) return frame;
    }
    return frameDurations.length - 1;
  }

  @override
  State<CcThanksAnimation> createState() => _CcThanksAnimationState();
}

class _CcThanksAnimationState extends State<CcThanksAnimation>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: CcThanksAnimation.duration,
  );
  ImageStream? _stream;
  ImageInfo? _image;
  late final ImageStreamListener _listener = ImageStreamListener(
    _onImage,
    onError: (Object error, StackTrace? stackTrace) {
      Log.e('CC 娘动画图集加载失败', error: error, stackTrace: stackTrace);
    },
  );
  bool _reduceMotion = false;
  bool _visible = true;
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    _visible = TickerMode.of(context);
    // 静态模式不解码整张图集, 用户恢复动画后再懒加载.
    if (!_reduceMotion && _stream == null) {
      _stream = const AssetImage(CcThanksAnimation.spriteAsset).resolve(
        createLocalImageConfiguration(context),
      );
      _stream!.addListener(_listener);
    }
    _syncPlayback();
  }

  void _onImage(ImageInfo image, bool synchronousCall) {
    if (!mounted) {
      image.dispose();
      return;
    }
    final previous = _image;
    setState(() => _image = image);
    previous?.dispose();
    _syncPlayback();
  }

  @override
  void didUpdateWidget(CcThanksAnimation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.replay != oldWidget.replay) {
      _controller.value = 0;
      _syncPlayback();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _syncPlayback();
  }

  void _syncPlayback() {
    if (_reduceMotion || !_visible || !_foreground || _image == null) {
      _controller.stop();
      if (_reduceMotion) _controller.value = 0;
    } else if (!_controller.isCompleted && !_controller.isAnimating) {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stream?.removeListener(_listener);
    _controller.dispose();
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      image: true,
      label: 'CC 娘鞠躬比心, 感谢你支持小站',
      child: ExcludeSemantics(
        child: RepaintBoundary(
          child: AspectRatio(
            aspectRatio: 1,
            child: _reduceMotion || _image == null
                ? Image.asset(
                    CcThanksAnimation.stillAsset,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) => const Center(
                      child: Icon(Icons.favorite_outline, size: 64),
                    ),
                  )
                : CustomPaint(
                    painter: _ThanksFramePainter(
                      image: _image!.image,
                      animation: _controller,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _ThanksFramePainter extends CustomPainter {
  _ThanksFramePainter({required this.image, required this.animation})
      : super(repaint: animation);

  final ui.Image image;
  final Animation<double> animation;

  @override
  void paint(Canvas canvas, Size size) {
    final elapsed = Duration(
      milliseconds: (animation.value * CcThanksAnimation.duration.inMilliseconds)
          .round(),
    );
    final frame = CcThanksAnimation.frameAt(elapsed);
    final width = image.width / 3;
    final height = image.height / 3;
    final source = Rect.fromLTWH(
      (frame % 3) * width,
      (frame ~/ 3) * height,
      width,
      height,
    );
    canvas.drawImageRect(
      image,
      source,
      Offset.zero & size,
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  @override
  bool shouldRepaint(_ThanksFramePainter oldDelegate) =>
      image != oldDelegate.image || animation != oldDelegate.animation;
}
