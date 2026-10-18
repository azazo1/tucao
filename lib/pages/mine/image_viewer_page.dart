import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tucao/services/image_save_service.dart';
import 'package:tucao/utils/error_text.dart';
import 'package:tucao/utils/logger.dart';

/// 单张图片的全屏查看.
///
/// 可以双指缩放与拖动; 长按图片 (或点右上角按钮) 保存到系统相册.
class ImageViewerPage extends StatefulWidget {
  const ImageViewerPage({
    super.key,
    required this.url,
    this.title,
    this.prefix,
  });

  /// 图片地址.
  final String url;

  /// 标题栏文案, 例如 "我的横幅".
  final String? title;

  /// 保存文件名前缀, 便于在相册里区分来源.
  final String? prefix;

  @override
  State<ImageViewerPage> createState() => _ImageViewerPageState();
}

class _ImageViewerPageState extends State<ImageViewerPage> {
  bool _saving = false;

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
        actions: [
          IconButton(
            tooltip: '保存到相册',
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.download_outlined),
          ),
        ],
      ),
      body: GestureDetector(
        onLongPress: _saving ? null : _save,
        child: Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                minScale: 1,
                maxScale: 5,
                child: Center(
                  child: CachedNetworkImage(
                    imageUrl: widget.url,
                    fit: BoxFit.contain,
                    placeholder: (context, url) => const Center(
                      child: CircularProgressIndicator(color: Colors.white70),
                    ),
                    errorWidget: (context, url, error) => const Center(
                      child: Text(
                        '图片加载失败',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 24,
              child: Text(
                '长按图片可保存到相册',
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
