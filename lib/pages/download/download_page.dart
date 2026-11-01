import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tucao/common/adaptive.dart';
import 'package:tucao/models/download_task.dart';
import 'package:tucao/pages/download/download_actions.dart';
import 'package:tucao/pages/download/downloading_page.dart';
import 'package:tucao/pages/download/offline_video_page.dart';
import 'package:tucao/pages/download/widgets/cached_video_tile.dart';
import 'package:tucao/pages/download/widgets/download_task_tile.dart';
import 'package:tucao/pages/video/video_page.dart';
import 'package:tucao/utils/logger.dart';

/// 离线缓存: 上方是缓存中的任务, 下方按视频分组列出已缓存内容.
class DownloadPage extends StatefulWidget {
  const DownloadPage({super.key});

  /// 主页只露出这么多条缓存中任务, 其余进缓存队列页查看.
  static const previewCount = 3;

  @override
  State<DownloadPage> createState() => _DownloadPageState();
}

class _DownloadPageState extends State<DownloadPage> with DownloadActions {
  bool _initializing = false;

  Future<void> _initialize() async {
    if (_initializing || !onTop) {
      return;
    }
    setState(() => _initializing = true);
    try {
      await downloads.initialize();
    } catch (error, stackTrace) {
      Log.e('重新加载缓存失败', error: error, stackTrace: stackTrace);
      notify('缓存加载失败, 请稍后重试');
    } finally {
      if (mounted) {
        setState(() => _initializing = false);
      }
    }
  }

  Future<void> _open(String hid, {int? part}) =>
      perform('video-$hid', () => OfflineVideoPage.open(context, hid, part: part));

  Future<void> _more(CachedVideo group) async {
    final action = await showCachedVideoSheet(
      context,
      group: group,
      onPart: (task) => unawaited(_open(group.hid, part: task.part)),
      onRemovePart: (task) => unawaited(removeTask(task)),
    );
    if (action == null || !onTop) {
      return;
    }
    switch (action) {
      case CachedVideoAction.play:
        await _open(group.hid);
      case CachedVideoAction.online:
        VideoPage.openByHid(group.hid);
      case CachedVideoAction.refresh:
        await _refresh(group);
      case CachedVideoAction.removeAll:
        await _removeAll(group);
    }
  }

  Future<void> _refresh(CachedVideo group) => perform(
    'video-${group.hid}',
    () async {
      Log.i('用户更新缓存附属数据 ${group.hid}');
      final updated = await downloads.refreshExtras(group.hid);
      notify(
        updated == group.tasks.length
            ? '弹幕与信息已更新'
            : '信息已更新, ${group.tasks.length - updated} 个分P弹幕更新失败',
      );
    },
    failure: '更新失败, 请检查网络后重试',
  );

  Future<void> _removeAll(CachedVideo group) =>
      perform('video-${group.hid}', () async {
        final count = group.tasks.length;
        if (!await confirmRemove(
          count > 1 ? '将删除这个视频已缓存的 $count 个分P, 确定继续吗?' : '将删除这个视频的本地缓存, 确定继续吗?',
        )) {
          return;
        }
        Log.i('用户删除视频全部缓存 ${group.hid}');
        for (final task in group.tasks) {
          await downloads.remove(task.id);
        }
        notify('缓存已删除');
      });

  void _showInfo() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('关于离线缓存'),
        content: const Text(
          '缓存保存在 Android/data 下的应用专属目录, 卸载应用时一并清除.\n\n'
          '仅在应用前台时下载. 点击缓存中的任务可以暂停或继续, '
          '继续时从已下载的位置接着下载, 视频源不支持断点续传时才会从头开始.\n\n'
          '缓存时会一并保存封面, 简介与弹幕, 离线时也能带弹幕播放. '
          '弹幕过时可在已缓存视频的更多菜单里更新.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('离线缓存'),
        actions: [
          batchAction(),
          IconButton(
            tooltip: '说明',
            onPressed: _showInfo,
            icon: const Icon(Icons.info_outline),
          ),
        ],
      ),
      body: Obx(() {
        if (!downloads.ready.value) {
          return _buildUnavailable();
        }
        final items = downloads.items.toList();
        final pending = items
            .where((task) => task.status != DownloadStatus.completed)
            .toList();
        final groups = _group(
          items.where((task) => task.status == DownloadStatus.completed),
        );
        if (pending.isEmpty && groups.isEmpty) {
          return _buildEmpty();
        }
        return _buildList(pending, groups);
      }),
    );
  }

  static List<CachedVideo> _group(Iterable<DownloadTask> completed) {
    final byHid = <String, List<DownloadTask>>{};
    for (final task in completed) {
      byHid.putIfAbsent(task.hid, () => []).add(task);
    }
    return [
      for (final entry in byHid.entries) CachedVideo(entry.key, entry.value),
    ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Widget _buildList(List<DownloadTask> pending, List<CachedVideo> groups) {
    final side = Adaptive.sidePadding(context);
    final preview = pending.take(DownloadPage.previewCount).toList();
    return ListView(
      padding: EdgeInsets.fromLTRB(side, 4, side, 24),
      children: [
        if (pending.isNotEmpty) ...[
          _SectionHeader(
            title: '正在缓存',
            count: pending.length,
            onMore: pending.length > preview.length
                ? () => Get.to(() => const DownloadingPage())
                : null,
          ),
          for (final task in preview)
            DownloadTaskTile(
              key: ValueKey(task.id),
              task: task,
              busy: busy.contains(task.id),
              onToggle: () => unawaited(toggle(task)),
              onRemove: () => unawaited(removeTask(task)),
            ),
        ],
        _SectionHeader(title: '已缓存视频', count: groups.length),
        if (groups.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Center(
              child: Text(
                '下载完成的视频会出现在这里',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          )
        else
          for (final group in groups)
            CachedVideoTile(
              key: ValueKey('cached-${group.hid}'),
              group: group,
              busy: busy.contains('video-${group.hid}'),
              onOpen: () => unawaited(_open(group.hid)),
              onMore: () => unawaited(_more(group)),
            ),
      ],
    );
  }

  Widget _buildEmpty() {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.download_for_offline_outlined,
              size: 56,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text('还没有离线缓存', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              '在播放页右上角的更多菜单里选择缓存',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUnavailable() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(downloads.initializationError.value ?? '缓存加载失败或尚未就绪'),
          const SizedBox(height: 8),
          FilledButton(
            key: const ValueKey('download-initialize'),
            onPressed: _initializing ? null : _initialize,
            child: _initializing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('重新加载'),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.count, this.onMore});

  final String title;
  final int count;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 4, 4),
      child: Row(
        children: [
          Text(title, style: theme.textTheme.titleSmall),
          const SizedBox(width: 6),
          Text(
            '$count',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const Spacer(),
          if (onMore != null)
            TextButton(
              key: const ValueKey('download-show-all'),
              onPressed: onMore,
              child: const Text('全部'),
            ),
        ],
      ),
    );
  }
}
