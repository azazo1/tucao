import 'package:flutter/material.dart';
import 'package:tucao/models/video.dart';
import 'package:tucao/common/style.dart';
import 'package:tucao/pages/video/video_page.dart';
import 'package:tucao/utils/date_utils.dart';
import 'package:tucao/utils/utils.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// 视频封面.
///
/// 站点列表接口返回的多是原图, 详情接口返回的是缩略图,
/// 这里统一按 [Style.coverAspectRatio] 裁切显示.
class VideoCover extends StatelessWidget {
  const VideoCover({
    super.key,
    required this.url,
    this.aspectRatio = Style.coverAspectRatio,
    this.radius = Style.cardRadius,
    this.overlay,
    this.fit = BoxFit.cover,
  });

  final String url;
  final double aspectRatio;
  final double radius;

  /// 叠加在封面右下角的内容, 例如时长.
  final Widget? overlay;

  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: AspectRatio(
        aspectRatio: aspectRatio,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (url.isEmpty)
              ColoredBox(color: scheme.surfaceContainerHighest)
            else
              CachedNetworkImage(
                imageUrl: url,
                fit: fit,
                fadeInDuration: const Duration(milliseconds: 150),
                placeholder: (context, url) =>
                    ColoredBox(color: scheme.surfaceContainerHighest),
                errorWidget: (context, url, error) => ColoredBox(
                  color: scheme.surfaceContainerHighest,
                  child: Icon(
                    Icons.broken_image_outlined,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            if (overlay != null)
              Positioned(right: 6, bottom: 6, child: overlay!),
          ],
        ),
      ),
    );
  }
}

/// 封面右下角的计数标签.
class CoverBadge extends StatelessWidget {
  const CoverBadge({super.key, required this.text, this.icon});

  final String text;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 11, color: Colors.white),
              const SizedBox(width: 3),
            ],
            Text(
              text,
              style: const TextStyle(fontSize: 11, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}

/// 首页等信息流使用的竖版视频卡片.
class VideoCardVertical extends StatelessWidget {
  const VideoCardVertical({super.key, required this.video, this.onTap});

  final VideoModel video;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return InkWell(
      onTap: onTap ?? () => VideoPage.open(video),
      borderRadius: BorderRadius.circular(Style.cardRadius),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          VideoCover(
            url: video.cover,
            overlay: CoverBadge(
              text: Utils.formatCount(video.danmakuCount),
              icon: Icons.subtitles_outlined,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            video.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.3),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(
                Icons.play_circle_outline,
                size: 13,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 3),
              Text(
                Utils.formatCount(video.playCount),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              if (video.createTime > 0)
                Text(
                  DateUtil.relative(video.createTime),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 搜索与排行榜等列表使用的横版视频条目.
class VideoCardHorizontal extends StatelessWidget {
  const VideoCardHorizontal({
    super.key,
    required this.video,
    this.onTap,
    this.showDescription = false,
  });

  final VideoModel video;
  final VoidCallback? onTap;
  final bool showDescription;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return InkWell(
      onTap: onTap ?? () => VideoPage.open(video),
      borderRadius: BorderRadius.circular(Style.cardRadius),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 148,
              child: VideoCover(
                url: video.cover,
                overlay: CoverBadge(
                  text: Utils.formatCount(video.danmakuCount),
                  icon: Icons.subtitles_outlined,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    video.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      height: 1.35,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (showDescription && video.description.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      video.description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(
                        Icons.play_circle_outline,
                        size: 13,
                        color: scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        Utils.formatCount(video.playCount),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      if (video.userName.isNotEmpty) ...[
                        const SizedBox(width: 10),
                        Flexible(
                          child: Text(
                            video.userName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (video.partCount > 1) ...[
                    const SizedBox(height: 4),
                    Text(
                      '共 ${video.partCount} P',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 列表底部的加载状态.
class LoadMoreFooter extends StatelessWidget {
  const LoadMoreFooter({
    super.key,
    required this.loading,
    required this.hasMore,
    this.onRetry,
  });

  final bool loading;
  final bool hasMore;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (!hasMore) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: Text(
            '没有更多了',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: TextButton(onPressed: onRetry, child: const Text('加载更多')),
      ),
    );
  }
}
