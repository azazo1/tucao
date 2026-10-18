import 'dart:ui' show lerpDouble;

import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tucao/services/image_save_service.dart';
import 'package:tucao/utils/error_text.dart';
import 'package:tucao/utils/logger.dart';

/// 单张图片的全屏查看.
///
/// 手势交给 extended_image: 双指缩放, 放大后拖动. 双击放大与还原由本页做
/// 补间动画, 因为库自身只在缩放越界时才动画, 范围内的双击会直接跳变, 手感很硬.
/// 长按弹出菜单, 菜单里可以保存到系统相册.
class ImageViewerPage extends StatefulWidget {
  const ImageViewerPage({
    super.key,
    required this.url,
    this.title,
    this.prefix,
  });

  /// 图片地址.
  final String url;

  /// 标题栏文案, 例如 "某某 的头像".
  final String? title;

  /// 保存文件名前缀, 便于在相册里区分来源.
  final String? prefix;

  @override
  State<ImageViewerPage> createState() => _ImageViewerPageState();
}

/// 长按菜单里能做的事.
enum _ViewerAction { save }

class _ImageViewerPageState extends State<ImageViewerPage>
    with SingleTickerProviderStateMixin {
  final _gestureKey = GlobalKey<ExtendedImageGestureState>();

  bool _saving = false;

  /// 双击放大到的倍数.
  static const _doubleTapScale = 2.5;

  /// 双击缩放的补间, 时长取系统图片查看的常见值.
  late final AnimationController _zoomController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );

  VoidCallback? _zoomTick;

  @override
  void dispose() {
    _stopZoomAnimation();
    _zoomController.dispose();
    super.dispose();
  }

  void _stopZoomAnimation() {
    final tick = _zoomTick;
    if (tick != null) {
      _zoomController.removeListener(tick);
      _zoomTick = null;
    }
    _zoomController.stop();
  }

  /// 双击: 已放大就平滑还原, 否则平滑放大到点击位置.
  void _handleDoubleTap(ExtendedImageGestureState state) {
    final details = state.gestureDetails;
    final currentScale = details?.totalScale ?? 1;
    final currentOffset = details?.offset ?? Offset.zero;
    if (currentScale > 1.05) {
      _animateZoom(state, targetScale: 1, targetOffset: Offset.zero);
      return;
    }
    // 按下位置与 offset 是同一套坐标, 用它保证手指下面那个点不动.
    final focal = state.pointerDownPosition;
    if (focal == null) {
      _animateZoom(
        state,
        targetScale: _doubleTapScale,
        targetOffset: Offset.zero,
      );
      return;
    }
    final normalized = (focal - currentOffset) / currentScale;
    _animateZoom(
      state,
      targetScale: _doubleTapScale,
      targetOffset: focal - normalized * _doubleTapScale,
    );
  }

  /// 把缩放倍数与偏移量从当前值补间到目标值.
  void _animateZoom(
    ExtendedImageGestureState state, {
    required double targetScale,
    required Offset targetOffset,
  }) {
    _stopZoomAnimation();
    final details = state.gestureDetails;
    final startScale = details?.totalScale ?? 1;
    final startOffset = details?.offset ?? Offset.zero;
    if ((startScale - targetScale).abs() < 0.001 &&
        (startOffset - targetOffset).distance < 0.5) {
      return;
    }
    _zoomTick = () {
      final t = Curves.easeOutCubic.transform(_zoomController.value);
      final scale = lerpDouble(startScale, targetScale, t) ?? targetScale;
      final offset = Offset.lerp(startOffset, targetOffset, t) ?? targetOffset;
      final target = _gestureKey.currentState;
      if (target == null) {
        return;
      }
      target.gestureDetails = GestureDetails(
        offset: offset,
        totalScale: scale,
        actionType: ActionType.zoom,
        // false 表示位移来自动画而不是用户拖动.
        userOffset: false,
        initialAlignment: InitialAlignment.center,
      );
    };
    _zoomController.addListener(_zoomTick!);
    _zoomController.forward(from: 0);
  }

  /// 长按图片时弹出可选操作, 而不是直接保存.
  Future<void> _showActions() async {
    final action = await showModalBottomSheet<_ViewerAction>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.title != null && widget.title!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Text(
                  widget.title!,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ListTile(
              leading: const Icon(Icons.download_outlined),
              title: const Text('保存到相册'),
              onTap: () => Navigator.of(sheetContext).pop(_ViewerAction.save),
            ),
            ListTile(
              leading: const Icon(Icons.close),
              title: const Text('取消'),
              onTap: () => Navigator.of(sheetContext).pop(),
            ),
          ],
        ),
      ),
    );
    if (action == _ViewerAction.save) {
      await _save();
    }
  }

  Future<void> _save() async {
    if (_saving) {
      return;
    }
    setState(() => _saving = true);
    try {
      final location = await ImageSaveService.saveUrl(
        widget.url,
        prefix: widget.prefix ?? 'tucao',
      );
      Get.snackbar('已保存', location, duration: const Duration(seconds: 3));
    } catch (e, stackTrace) {
      Log.e('保存图片失败', error: e, stackTrace: stackTrace);
      Get.snackbar('保存失败', errorText(e));
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        title: widget.title == null ? null : Text(widget.title!),
      ),
      body: Listener(
        // 动画途中用户按下就立刻停, 免得和自己的拖动打架.
        onPointerDown: (_) => _stopZoomAnimation(),
        child: GestureDetector(
          onLongPress: _saving ? null : _showActions,
          child: Stack(
            children: [
              Positioned.fill(child: _buildImage()),
              Positioned(
                left: 0,
                right: 0,
                bottom: 24,
                child: Text(
                  '双击放大, 长按保存到相册',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.7),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImage() {
    return ExtendedImage.network(
      widget.url,
      fit: BoxFit.contain,
      mode: ExtendedImageMode.gesture,
      extendedImageGestureKey: _gestureKey,
      onDoubleTap: _handleDoubleTap,
      initGestureConfigHandler: (state) => GestureConfig(
        minScale: 0.8,
        maxScale: 5,
        initialScale: 1,
        inPageView: false,
        initialAlignment: InitialAlignment.center,
        speed: 1,
        inertialSpeed: 100,
      ),
      loadStateChanged: (state) {
        switch (state.extendedImageLoadState) {
          case LoadState.loading:
            return const Center(
              child: CircularProgressIndicator(color: Colors.white70),
            );
          case LoadState.failed:
            return const Center(
              child: Text(
                '图片加载失败',
                style: TextStyle(color: Colors.white70),
              ),
            );
          case LoadState.completed:
            // 返回 null 表示走默认渲染.
            return null;
        }
      },
    );
  }
}
