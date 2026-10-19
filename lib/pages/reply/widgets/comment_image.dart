import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tucao/pages/mine/image_viewer_page.dart';
import 'package:tucao/pages/reply/reply_content.dart';

/// 评论里贴的图片.
///
/// 站点网页端把这类图片压成 100 像素宽的缩略图, 点一下放大. 这里是同样的
/// 思路: 缩略图统一以高度定尺, 宽度跟随原始宽高比, 过宽或过窄的图会收进
/// 区间内; 点击进入全屏查看, 缩放与保存由查看页负责.
///
/// 站外的图片不自动联网, 先显示占位, 等用户点过才去取, 免得别人的一条评论
/// 就让本机向任意主机发请求. 解码尺寸也跟着显示尺寸收窄, 超大图不会整张
/// 进内存.
class CommentImage extends StatefulWidget {
  const CommentImage({super.key, required this.url, this.height = 96});

  /// 图片地址, 需要是绝对地址.
  final String url;

  /// 缩略图高度, 楼中楼这类紧凑布局可以调小.
  final double height;

  @override
  State<CommentImage> createState() => _CommentImageState();
}

class _CommentImageState extends State<CommentImage> {
  /// 原始宽高比, 尺寸没解析出来之前按正方形占位.
  double _aspectRatio = 1;

  /// 是否允许取图, 站外图片要等用户点一下.
  late bool _allowed = isSiteImage(widget.url);

  ImageStream? _stream;
  ImageStreamListener? _listener;

  /// 已经解析过尺寸的地址, 依赖变化时用来跳过重复解析.
  String? _resolvedUrl;

  /// 缩略图宽度区间, 避免横长图铺满一行, 也避免细长图变成一条线.
  static const _minWidth = 48.0;
  static const _maxWidth = 220.0;

  /// 只为取宽高比而做的预解析宽度, 不需要解出原图.
  static const _probeWidth = 160;

  /// 磁盘缓存里保留的最大宽度, 免得原图长期占地方.
  static const _diskWidth = 720;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 图片地址与屏幕像素比都确定了才解析, 这样和列表里的图共用同一份缓存.
    _syncResolution();
  }

  @override
  void didUpdateWidget(covariant CommentImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _aspectRatio = 1;
      _allowed = isSiteImage(widget.url);
      _syncResolution();
    }
  }

  @override
  void dispose() {
    _detach();
    super.dispose();
  }

  void _detach() {
    final stream = _stream;
    final listener = _listener;
    if (stream != null && listener != null) {
      stream.removeListener(listener);
    }
    _stream = null;
    _listener = null;
  }

  /// 每个地址只解析一次, 依赖变化时不必反复订阅.
  void _syncResolution() {
    if (!_allowed || _resolvedUrl == widget.url) {
      return;
    }
    _resolvedUrl = widget.url;
    _resolveAspectRatio();
  }

  /// 单独解析一次图片只为了拿原始尺寸, 缩略图按它决定宽高.
  void _resolveAspectRatio() {
    _detach();
    final provider = ResizeImage(
      CachedNetworkImageProvider(widget.url),
      width: _probeWidth,
      allowUpscaling: false,
    );
    final stream = provider.resolve(createLocalImageConfiguration(context));
    final listener = ImageStreamListener(
      (info, _) {
        final height = info.image.height;
        if (height <= 0) {
          return;
        }
        // 图片已在缓存里时回调是同步的, 放到下一个微任务再改状态,
        // 免得在依赖变化或构建期间触发重建.
        scheduleMicrotask(() => _applyRatio(info.image.width / height));
      },
      onError: (error, stackTrace) {
        // 取不到尺寸就按正方形占位, 加载失败由 errorWidget 兜底.
      },
    );
    stream.addListener(listener);
    _stream = stream;
    _listener = listener;
  }

  void _applyRatio(double ratio) {
    if (!mounted || ratio == _aspectRatio) {
      return;
    }
    setState(() => _aspectRatio = ratio);
  }

  double get _width =>
      (widget.height * _aspectRatio).clamp(_minWidth, _maxWidth);

  /// 站外图片: 先记下用户已经同意, 再开始取图.
  void _allow() {
    if (_allowed) {
      return;
    }
    setState(() => _allowed = true);
    _syncResolution();
  }

  void _open() {
    Get.to(
      () => ImageViewerPage(
        url: widget.url,
        title: '评论图片',
        prefix: 'tucao-comment',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = _width;
    if (!_allowed) {
      return _buildPlaceholder(width);
    }
    final scheme = Theme.of(context).colorScheme;
    final height = width / _aspectRatio;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
      child: InkWell(
        onTap: _open,
        borderRadius: BorderRadius.circular(6),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            width: width,
            height: height,
            child: CachedNetworkImage(
              imageUrl: widget.url,
              fit: BoxFit.cover,
              memCacheWidth: (width * dpr).round(),
              maxWidthDiskCache: _diskWidth,
              placeholder: (context, url) => ColoredBox(
                color: scheme.surfaceContainerHighest,
                child: const Center(
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
              errorWidget: (context, url, error) => ColoredBox(
                color: scheme.surfaceContainerHighest,
                child: Icon(
                  Icons.broken_image_outlined,
                  size: 20,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 站外图片的占位, 点一下才开始取图.
  Widget _buildPlaceholder(double width) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
      child: InkWell(
        onTap: _allow,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          width: width,
          height: width / _aspectRatio,
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.image_outlined,
                size: 20,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(height: 4),
              Text(
                '点击加载',
                style: TextStyle(
                  fontSize: 11,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
