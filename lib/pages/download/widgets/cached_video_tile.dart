import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tucao/common/widgets/video_card.dart';
import 'package:tucao/models/download_task.dart';
import 'package:tucao/services/download/download_service.dart';
import 'package:tucao/utils/utils.dart';

/// 一个视频下已经缓存好的分P, 按分P序号排列.
class CachedVideo {
  CachedVideo(this.hid, List<DownloadTask> tasks)
    : tasks = [...tasks]..sort((a, b) => a.part.compareTo(b.part));

  final String hid;
  final List<DownloadTask> tasks;

  String get title => tasks.first.title;
  int get size => tasks.fold(0, (sum, task) => sum + task.received);

  /// 按首个分P的加入时间分组排序, 新加入的在前.
  int get createdAt => tasks.map((task) => task.createdAt).reduce(
    (a, b) => a > b ? a : b,
  );
}

/// 已缓存视频的一行: 封面, 标题, 分P数, 大小与作者.
class CachedVideoTile extends StatelessWidget {
  const CachedVideoTile({
    super.key,
    required this.group,
    required this.busy,
    required this.onOpen,
    required this.onMore,
  });

  final CachedVideo group;
  final bool busy;
  final VoidCallback onOpen;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final service = DownloadService.instance;
    final style = theme.textTheme.labelSmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    final count = group.tasks.length;
    return InkWell(
      onTap: busy ? null : onOpen,
      onLongPress: busy ? null : onMore,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: Obx(() {
          final video = service.videos[group.hid];
          final user = video?.userName ?? '';
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 140,
                child: VideoCover(
                  url: video?.cover ?? '',
                  file: service.covers.contains(group.hid)
                      ? service.coverFile(group.hid)
                      : null,
                  aspectRatio: 16 / 10,
                  radius: 6,
                  overlay: count > 1
                      ? CoverBadge(text: '$count P', icon: Icons.video_library)
                      : null,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      video?.title ?? group.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      count == 1
                          ? 'P${group.tasks.first.part + 1} · ${Utils.formatBytes(group.size)}'
                          : '$count 个分P · ${Utils.formatBytes(group.size)}',
                      style: style,
                    ),
                    if (user.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        user,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: style,
                      ),
                    ],
                  ],
                ),
              ),
              SizedBox(
                width: 40,
                height: 40,
                child: busy
                    ? const Padding(
                        padding: EdgeInsets.all(10),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : IconButton(
                        key: ValueKey('cached-more-${group.hid}'),
                        tooltip: '更多',
                        onPressed: onMore,
                        icon: const Icon(Icons.more_vert, size: 20),
                      ),
              ),
            ],
          );
        }),
      ),
    );
  }
}

/// 已缓存视频的更多操作.
enum CachedVideoAction { play, refresh, online, removeAll }

/// 更多操作面板: 视频级操作在上, 各分P的播放与删除在下.
///
/// 返回选中的视频级操作, 或在 [onPart] / [onRemovePart] 里直接处理分P.
Future<CachedVideoAction?> showCachedVideoSheet(
  BuildContext context, {
  required CachedVideo group,
  required void Function(DownloadTask task) onPart,
  required void Function(DownloadTask task) onRemovePart,
}) {
  return showModalBottomSheet<CachedVideoAction>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) {
      final theme = Theme.of(sheetContext);
      return ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.75,
        ),
        child: SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  group.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall,
                ),
              ),
              ListTile(
                leading: const Icon(Icons.play_circle_outline),
                title: const Text('离线播放'),
                onTap: () =>
                    Navigator.of(sheetContext).pop(CachedVideoAction.play),
              ),
              ListTile(
                key: const ValueKey('cached-refresh'),
                leading: const Icon(Icons.sync),
                title: const Text('更新弹幕与信息'),
                subtitle: const Text('重新拉取封面, 简介与各分P弹幕'),
                onTap: () =>
                    Navigator.of(sheetContext).pop(CachedVideoAction.refresh),
              ),
              ListTile(
                leading: const Icon(Icons.public),
                title: const Text('在线观看'),
                onTap: () =>
                    Navigator.of(sheetContext).pop(CachedVideoAction.online),
              ),
              ListTile(
                key: const ValueKey('cached-remove-all'),
                leading: Icon(
                  Icons.delete_outline,
                  color: theme.colorScheme.error,
                ),
                title: Text(
                  group.tasks.length > 1 ? '删除全部分P' : '删除缓存',
                  style: TextStyle(color: theme.colorScheme.error),
                ),
                onTap: () =>
                    Navigator.of(sheetContext).pop(CachedVideoAction.removeAll),
              ),
              if (group.tasks.length > 1) ...[
                const Divider(),
                for (final task in group.tasks)
                  ListTile(
                    key: ValueKey('cached-part-${task.id}'),
                    dense: true,
                    title: Text(
                      task.partTitle.isEmpty
                          ? 'P${task.part + 1}'
                          : 'P${task.part + 1} ${task.partTitle}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(Utils.formatBytes(task.received)),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      onPart(task);
                    },
                    trailing: IconButton(
                      key: ValueKey('download-remove-${task.id}'),
                      tooltip: '删除该分P',
                      icon: const Icon(Icons.delete_outline, size: 20),
                      onPressed: () {
                        Navigator.of(sheetContext).pop();
                        onRemovePart(task);
                      },
                    ),
                  ),
              ],
            ],
          ),
        ),
      );
    },
  );
}
