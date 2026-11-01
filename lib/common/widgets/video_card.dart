import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tucao/models/video.dart';
import 'package:tucao/common/style.dart';
import 'package:tucao/common/widgets/cover_hero.dart';
import 'package:tucao/common/widgets/video_block_sheet.dart';
import 'package:tucao/pages/mine/image_viewer_page.dart';
import 'package:tucao/pages/video/video_page.dart';
import 'package:tucao/utils/clipboard.dart';
import 'package:tucao/utils/site_links.dart';
import 'package:tucao/utils/utils.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// 视频卡片长按菜单的动作.
enum _CardAction { viewCover, copyTitle, copyLink, block }

/// 视频卡片长按菜单: 查看封面图, 复制标题, 复制视频链接与屏蔽.
Future<void> showVideoCardMenu(BuildContext context, VideoModel video) async {
  final hasCover = video.cover.isNotEmpty;
  final action = await showModalBottomSheet<_CardAction>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      final scheme = Theme.of(sheetContext).colorScheme;
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                video.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(sheetContext).textTheme.titleSmall,
              ),
            ),
            if (hasCover)
              ListTile(
                leading: const Icon(Icons.image_outlined),
                title: const Text('查看封面图'),
                onTap: () =>
                    Navigator.pop(sheetContext, _CardAction.viewCover),
              ),
            ListTile(
              leading: const Icon(Icons.title),
              title: const Text('复制标题'),
              onTap: () => Navigator.pop(sheetContext, _CardAction.copyTitle),
            ),
            ListTile(
              leading: const Icon(Icons.link),
              title: const Text('复制视频链接'),
              onTap: () => Navigator.pop(sheetContext, _CardAction.copyLink),
            ),
            ListTile(
              leading: Icon(Icons.block, color: scheme.error),
              title: Text('屏蔽', style: TextStyle(color: scheme.error)),
              subtitle: const Text('不再出现在首页, 番组, 搜索与排行等列表'),
              onTap: () => Navigator.pop(sheetContext, _CardAction.block),
            ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
  if (action == null || !context.mounted) {
    return;
  }
  switch (action) {
    case _CardAction.viewCover:
      Get.to(
        () => ImageViewerPage(
          url: video.cover,
          title: video.title,
          prefix: 'tucao-cover',
        ),
      );
    case _CardAction.copyTitle:
      await copyText(context, video.title);
    case _CardAction.copyLink:
      final uri = SiteLinks.video(video.hid);
      if (uri == null) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(
            content: Text('无法生成视频链接'),
            duration: Duration(seconds: 2),
          ),
        );
        return;
      }
      await copyText(context, uri.toString());
    case _CardAction.block:
      await showVideoBlockSheet(context, video);
  }
}

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
    this.bottom,
    this.fit = BoxFit.cover,
    this.heroTag,
  });

  /// 点进播放页时封面飞过去用的 tag, 只包住图片, 角标不跟着飞.
  final String? heroTag;

  final String url;
  final double aspectRatio;
  final double radius;

  /// 叠加在封面右下角的内容, 例如时长.
  final Widget? overlay;

  /// 贴着封面底边铺满宽度的内容, 例如观看进度条.
  final Widget? bottom;

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
              CoverHero.wrap(
                tag: heroTag,
                child: CachedNetworkImage(
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
              ),
            if (overlay != null)
              Positioned(right: 6, bottom: 6, child: overlay!),
            if (bottom != null)
              Positioned(left: 0, right: 0, bottom: 0, child: bottom!),
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
///
/// 结构参考 PiliPlus: 卡片自身有圆角与底色, 封面只圆上方两角,
/// 下方是带内边距的内容区, 依次是标题, 统计行与作者行;
/// 作者行只在取到作者名时出现, 新番时间表与新番索引的抓取结果里没有作者,
/// 这两处不会显示作者行.
class VideoCardVertical extends StatelessWidget {
  const VideoCardVertical({
    super.key,
    required this.video,
    this.onTap,
    this.onLongPress,
    this.badge,
    this.followed = false,
    this.showDanmakuCount = true,
    this.footerTrailing,
  });

  final VideoModel video;
  final VoidCallback? onTap;

  /// 长按操作, 默认为屏蔽弹层.
  final VoidCallback? onLongPress;

  /// 封面左上角的附加标签, 例如集数状态.
  final String? badge;

  /// 站点账号已追番, 封面右上角标出.
  final bool followed;

  /// 是否显示弹幕数, 封面角标与底部统计行都受它控制.
  ///
  /// 时间表的列表接口不给弹幕数, 恒为 0, 这类页面关掉.
  final bool showDanmakuCount;

  /// 底部信息行最右端的内容, 例如时间表的更新时刻.
  ///
  /// 放在播放数同一行的右侧, 用 Expanded 把统计行顶在左边.
  final Widget? footerTrailing;

  @override
  Widget build(BuildContext context) {
    return HeroLaunch(
      hid: video.hid,
      builder: (context, heroTag, launch) => _build(context, heroTag, launch),
    );
  }

  Widget _build(
    BuildContext context,
    String? heroTag,
    String Function() launch,
  ) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      // 网格用的是固定高度, 去掉 Card 默认的外边距, 避免卡片被压小.
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap ?? () => VideoPage.open(video, heroTag: launch()),
        onLongPress: onLongPress ?? () => showVideoCardMenu(context, video),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                // 卡片自身已裁圆角, 封面不再单独裁切.
                VideoCover(
                  url: video.cover,
                  radius: 0,
                  overlay: showDanmakuCount
                      ? CoverBadge(
                          text: Utils.formatCount(video.danmakuCount),
                          icon: Icons.subtitles_outlined,
                        )
                      : null,
                  heroTag: heroTag,
                ),
                if (badge != null && badge!.isNotEmpty)
                  Positioned(left: 6, top: 6, child: CoverBadge(text: badge!)),
                if (followed)
                  Positioned(
                    right: 6,
                    top: 6,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: scheme.primary,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        child: Text(
                          '已追',
                          style: TextStyle(
                            fontSize: 10,
                            color: scheme.onPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        video.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          height: 1.35,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: _StatRow(
                            video: video,
                            showDanmaku: showDanmakuCount,
                          ),
                        ),
                        if (footerTrailing != null) footerTrailing!,
                      ],
                    ),
                    if (video.userName.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Icon(
                            Icons.person_outline,
                            size: 12,
                            color: scheme.outline,
                          ),
                          const SizedBox(width: 3),
                          Expanded(
                            child: Text(
                              video.userName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: scheme.outline,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 卡片的统计行, 播放数与弹幕数.
class _StatRow extends StatelessWidget {
  const _StatRow({required this.video, this.showDanmaku = true});

  final VideoModel video;

  /// 是否显示弹幕数, 列表接口不给弹幕数时关掉.
  final bool showDanmaku;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = TextStyle(fontSize: 11, color: scheme.onSurfaceVariant);
    return Row(
      children: [
        Icon(Icons.play_circle_outline, size: 12, color: scheme.outline),
        const SizedBox(width: 2),
        Text(Utils.formatCount(video.playCount), style: style),
        if (showDanmaku) ...[
          const SizedBox(width: 8),
          Icon(Icons.subtitles_outlined, size: 12, color: scheme.outline),
          const SizedBox(width: 2),
          Text(Utils.formatCount(video.danmakuCount), style: style),
        ],
      ],
    );
  }
}

/// 搜索与排行榜等列表使用的横版视频条目.
class VideoCardHorizontal extends StatelessWidget {
  const VideoCardHorizontal({
    super.key,
    required this.video,
    this.onTap,
    this.onLongPress,
    this.showDescription = false,
    this.badge,
  });

  final VideoModel video;
  final VoidCallback? onTap;

  /// 长按操作, 默认为屏蔽弹层.
  final VoidCallback? onLongPress;

  final bool showDescription;

  /// 封面左上角的角标, 为空时不显示.
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return HeroLaunch(
      hid: video.hid,
      builder: (context, heroTag, launch) => _build(context, heroTag, launch),
    );
  }

  Widget _build(
    BuildContext context,
    String? heroTag,
    String Function() launch,
  ) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return InkWell(
      onTap: onTap ?? () => VideoPage.open(video, heroTag: launch()),
      onLongPress: onLongPress ?? () => showVideoCardMenu(context, video),
      borderRadius: BorderRadius.circular(Style.cardRadius),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 148,
              child: Stack(
                children: [
                  VideoCover(
                    url: video.cover,
                    overlay: CoverBadge(
                      text: Utils.formatCount(video.danmakuCount),
                      icon: Icons.subtitles_outlined,
                    ),
                    heroTag: heroTag,
                  ),
                  if (badge != null)
                    Positioned(
                      left: 6,
                      top: 6,
                      child: CoverBadge(text: badge!),
                    ),
                ],
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
