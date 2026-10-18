import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tucao/services/image_save_service.dart';
import 'package:tucao/utils/error_text.dart';
import 'package:tucao/utils/logger.dart';

/// 单张图片的全屏查看.
///
/// 手势交给 extended_image: 双指缩放, 双击放大到点击位置 (再双击还原),
/// 放大后可以拖动. 长按弹出菜单, 菜单里可以保存到系统相册.
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

class _ImageViewerPageState extends State<ImageViewerPage> {
  final _gestureKey = GlobalKey<ExtendedImageGestureState>();

  bool _saving = false;

  /// 双击放大到的倍数.
  static const _doubleTapScale = 2.5;

  /// 双击时当前已放大就还原, 否则放大到点击位置.
  void _handleDoubleTap(ExtendedImageGestureState state) {
    final scale = state.gestureDetails?.totalScale ?? 1;
    if (scale > _doubleTapScale * 0.9) {
      state.reset();
      return;
    }
    // 不传位置时按最后一次按下的位置放大, 也就是手指点的位置.
    state.handleDoubleTap(scale: _doubleTapScale);
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
      body: GestureDetector(
        onLongPress: _saving ? null : _showActions,
        child: Stack(
          children: [
            Positioned.fill(
              child: ExtendedImage.network(
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
                        child: CircularProgressIndicator(
                          color: Colors.white70,
                        ),
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
              ),
            ),
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
    );
  }
}
