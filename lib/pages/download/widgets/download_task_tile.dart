import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tucao/common/widgets/video_card.dart';
import 'package:tucao/models/download_task.dart';
import 'package:tucao/services/download/download_service.dart';
import 'package:tucao/utils/utils.dart';

/// 缓存中的一行: 封面, 标题, 分P, 进度与网速.
///
/// 点整行在暂停与继续之间切换, 右侧图标同样切换, 菜单里放删除.
class DownloadTaskTile extends StatelessWidget {
  const DownloadTaskTile({
    super.key,
    required this.task,
    required this.busy,
    required this.onToggle,
    required this.onRemove,
  });

  final DownloadTask task;
  final bool busy;
  final VoidCallback onToggle;
  final VoidCallback onRemove;

  bool get _running =>
      task.status == DownloadStatus.downloading ||
      task.status == DownloadStatus.queued;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final service = DownloadService.instance;
    final failed = task.status == DownloadStatus.failed;
    return InkWell(
      onTap: busy ? null : onToggle,
      onLongPress: busy ? null : onRemove,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 112,
              child: Obx(
                () => VideoCover(
                  url: service.videos[task.hid]?.cover ?? '',
                  file: service.covers.contains(task.hid)
                      ? service.coverFile(task.hid)
                      : null,
                  aspectRatio: 16 / 10,
                  radius: 6,
                  overlay: CoverBadge(text: 'P${task.part + 1}'),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    task.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                      height: 1.3,
                    ),
                  ),
                  if (task.partTitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      task.partTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      // 下载中且大小未知时走动画, 其余状态按已有字节画静止进度.
                      value: task.status == DownloadStatus.downloading
                          ? task.progress
                          : task.progress ?? 0,
                      minHeight: 3,
                      color: failed
                          ? scheme.error
                          : _running
                          ? null
                          : scheme.outline,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Obx(() => _statusLine(theme, service.speeds[task.id])),
                ],
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 40,
                  height: 40,
                  child: busy
                      ? const Padding(
                          padding: EdgeInsets.all(10),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : IconButton(
                          key: ValueKey('download-action-${task.id}'),
                          tooltip: _running ? '暂停' : '继续',
                          onPressed: onToggle,
                          icon: Icon(
                            _running
                                ? Icons.pause_circle_outline
                                : failed
                                ? Icons.refresh
                                : Icons.play_circle_outline,
                          ),
                        ),
                ),
                SizedBox(
                  width: 40,
                  height: 40,
                  child: IconButton(
                    key: ValueKey('download-remove-${task.id}'),
                    tooltip: '删除缓存',
                    onPressed: busy ? null : onRemove,
                    icon: const Icon(Icons.delete_outline, size: 20),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusLine(ThemeData theme, int? speed) {
    final scheme = theme.colorScheme;
    final style = theme.textTheme.labelSmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    final size = task.total > 0
        ? '${Utils.formatBytes(task.received)} / ${Utils.formatBytes(task.total)}'
        : task.received > 0
        ? Utils.formatBytes(task.received)
        : '';
    final (String state, Color? color) = switch (task.status) {
      DownloadStatus.queued => ('等待中', null),
      DownloadStatus.downloading => (
        speed == null ? '连接中' : '${Utils.formatBytes(speed)}/s',
        scheme.primary,
      ),
      DownloadStatus.paused => (task.received > 0 ? '已暂停, 点击继续' : '已暂停', null),
      DownloadStatus.failed => (task.error ?? '下载失败', scheme.error),
      DownloadStatus.completed => ('已完成', null),
    };
    return Row(
      children: [
        Expanded(
          child: Text(
            state,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: style?.copyWith(color: color ?? scheme.onSurfaceVariant),
          ),
        ),
        if (size.isNotEmpty) ...[
          const SizedBox(width: 8),
          Text(size, style: style),
        ],
      ],
    );
  }
}
