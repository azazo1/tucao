import 'dart:async';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:tucao/common/style.dart';

/// 用户横幅背景.
///
/// 站点上不少账号的横幅其实是一张近乎全黑的默认图, 直接铺在页头只会得到
/// 一块和页面背景同样黑的东西. 这里在图片解码后量一下平均亮度, 判定为暗图
/// 时就不铺它, 改用主题容器色的渐变; 没有地址或者加载失败同样走渐变.
///
/// 渐变始终画在最底下, 图片只在判定通过后才叠上去, 因此判定过程中不会出现
/// 先黑一下再变亮的情况.
class UserBanner extends StatefulWidget {
  const UserBanner({super.key, required this.url});

  /// 横幅地址, 为空时只画渐变.
  final String url;

  /// 判定为暗图的平均亮度上限, 取值范围是 0 到 255 的感知亮度.
  ///
  /// 取得偏小, 只兜住那种整张几乎全黑的图, 深色但正常的横幅仍然照常显示.
  static const darkLumaLimit = 36.0;

  /// 量亮度时的采样宽度, 只要看个大概, 不需要原图尺寸.
  static const _probeWidth = 24;

  @override
  State<UserBanner> createState() => _UserBannerState();
}

class _UserBannerState extends State<UserBanner> {
  /// 图片够亮, 可以铺上去.
  bool _usable = false;

  @override
  void initState() {
    super.initState();
    unawaited(_probe(widget.url));
  }

  @override
  void didUpdateWidget(covariant UserBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.url == oldWidget.url) {
      return;
    }
    _usable = false;
    unawaited(_probe(widget.url));
  }

  Future<void> _probe(String url) async {
    if (url.isEmpty) {
      return;
    }
    final luma = await _averageLuma(url);
    if (!mounted || widget.url != url) {
      return;
    }
    setState(() => _usable = luma != null && luma > UserBanner.darkLumaLimit);
  }

  /// 解码一张缩略图并求平均感知亮度, 取不到时返回 null.
  static Future<double?> _averageLuma(String url) async {
    final provider = ResizeImage(
      CachedNetworkImageProvider(url),
      width: UserBanner._probeWidth,
    );
    final image = await _resolve(provider);
    if (image == null) {
      return null;
    }
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) {
        return null;
      }
      final bytes = data.buffer.asUint8List();
      var sum = 0.0;
      var count = 0;
      for (var i = 0; i + 3 < bytes.length; i += 4) {
        // 透明像素在这里会算成全黑, 站点那张占位图正好也是这样判掉的.
        sum += 0.299 * bytes[i] + 0.587 * bytes[i + 1] + 0.114 * bytes[i + 2];
        count++;
      }
      return count == 0 ? null : sum / count;
    } finally {
      image.dispose();
    }
  }

  /// 等第一帧图片解出来, 失败返回 null.
  static Future<ui.Image?> _resolve(ImageProvider provider) {
    final completer = Completer<ui.Image?>();
    final stream = provider.resolve(ImageConfiguration.empty);
    late final ImageStreamListener listener;
    void finish(ui.Image? image) {
      if (completer.isCompleted) {
        return;
      }
      completer.complete(image);
      stream.removeListener(listener);
    }

    listener = ImageStreamListener(
      // 移除监听后原图可能被回收, 这里先加一次引用, 用完由调用方释放.
      (info, _) => finish(info.image.clone()),
      onError: (error, stackTrace) => finish(null),
    );
    stream.addListener(listener);
    return completer.future;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(gradient: Style.bannerGradient(scheme)),
        ),
        if (_usable)
          CachedNetworkImage(
            imageUrl: widget.url,
            fit: BoxFit.cover,
            fadeInDuration: const Duration(milliseconds: 150),
            // 渐变已经在下面, 占位与失败都不再画东西.
            placeholder: (context, url) => const SizedBox.shrink(),
            errorWidget: (context, url, error) => const SizedBox.shrink(),
          ),
      ],
    );
  }
}
