import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:tucao/common/widgets/cover_hero.dart';

/// 首帧出来前垫在画面下的模糊封面, 出画面后淡出.
///
/// 封面多半已被列表卡片缓存, 进入播放页几乎立即可见, 不会先看到一片黑.
/// 淡出结束后整层卸载, 播放中不再承担模糊的绘制开销.
class PlayerCover extends StatefulWidget {
  const PlayerCover({
    super.key,
    required this.url,
    required this.visible,
    this.heroTag,
    this.file,
  });

  final String url;

  /// 本地封面文件, 有时不走网络.
  final File? file;

  final bool visible;

  /// 列表封面飞进来时的落点, 见 [CoverHero].
  final String? heroTag;

  @override
  State<PlayerCover> createState() => _PlayerCoverState();
}

class _PlayerCoverState extends State<PlayerCover> {
  static const _fade = Duration(milliseconds: 300);

  /// 淡出已经结束, 子树可以卸载.
  late bool _gone = !widget.visible;

  @override
  void didUpdateWidget(covariant PlayerCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 切换分P时重新出现.
    if (widget.visible && _gone) {
      _gone = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final file = widget.file;
    if ((widget.url.isEmpty && file == null) || _gone) {
      return const SizedBox.shrink();
    }
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: widget.visible ? 1 : 0,
        duration: _fade,
        onEnd: () {
          if (mounted && !widget.visible) {
            setState(() => _gone = true);
          }
        },
        child: CoverHero.wrap(
          tag: widget.heroTag,
          child: ClipRect(
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: file != null
                  ? Image.file(
                      file,
                      fit: BoxFit.cover,
                      color: Colors.black38,
                      colorBlendMode: BlendMode.darken,
                      errorBuilder: (context, error, stackTrace) =>
                          const SizedBox.shrink(),
                    )
                  : CachedNetworkImage(
                      imageUrl: widget.url,
                      fit: BoxFit.cover,
                      color: Colors.black38,
                      colorBlendMode: BlendMode.darken,
                      fadeInDuration: const Duration(milliseconds: 150),
                      errorWidget: (context, url, error) =>
                          const SizedBox.shrink(),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
