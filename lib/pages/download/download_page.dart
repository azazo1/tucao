import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tucao/models/download_task.dart';
import 'package:tucao/pages/download/cached_video_page.dart';
import 'package:tucao/services/download/download_service.dart';
import 'package:tucao/utils/logger.dart';

/// 前台缓存任务与本地已缓存视频.
class DownloadPage extends StatefulWidget {
  const DownloadPage({super.key});

  @override
  State<DownloadPage> createState() => _DownloadPageState();
}

class _DownloadPageState extends State<DownloadPage> {
  final _service = DownloadService.instance;
  final _busy = <String>{};
  bool _initializing = false;

  bool get _current => mounted && ModalRoute.of(context)?.isCurrent == true;

  void _notify(String message) {
    if (_current) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _initialize() async {
    if (_initializing || !_current) {
      return;
    }
    setState(() => _initializing = true);
    try {
      await _service.initialize();
    } catch (error, stackTrace) {
      Log.e('重新加载缓存失败', error: error, stackTrace: stackTrace);
      _notify('缓存加载失败, 请稍后重试');
    } finally {
      if (mounted) {
        setState(() => _initializing = false);
      }
    }
  }

  Future<void> _perform(String id, Future<void> Function() action) async {
    if (_busy.contains(id) || !_current) {
      return;
    }
    setState(() => _busy.add(id));
    try {
      await action();
    } catch (error, stackTrace) {
      Log.e('缓存任务操作失败', error: error, stackTrace: stackTrace);
      _notify('操作失败, 请稍后重试');
    } finally {
      if (mounted) {
        setState(() => _busy.remove(id));
      }
    }
  }

  Future<void> _remove(DownloadTask task) => _perform(task.id, () async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除缓存'),
        content: Text('将删除 P${task.part + 1} 的缓存任务和本地文件, 确定继续吗?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !_current) {
      return;
    }
    await _service.remove(task.id);
    _notify('缓存已删除');
  });

  Future<void> _open(DownloadTask task) => _perform(task.id, () async {
    final file = await _service.localFile(task.id);
    if (!_current) {
      return;
    }
    if (file == null) {
      _notify('本地缓存文件缺失或不完整, 请从头重试');
      return;
    }
    Get.to(() => CachedVideoPage(task: task, file: file));
  });

  Widget _list(List<DownloadTask> tasks, {required bool completed}) {
    if (tasks.isEmpty) {
      return Center(child: Text(completed ? '还没有已缓存的视频' : '还没有缓存任务'));
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: tasks.length,
      separatorBuilder: (context, index) =>
          const Divider(height: 1, indent: 16),
      itemBuilder: (context, index) {
        final task = tasks[index];
        final busy = _busy.contains(task.id);
        final retry =
            task.status == DownloadStatus.paused ||
            task.status == DownloadStatus.failed;
        return _DownloadTile(
          key: ValueKey(task.id),
          task: task,
          busy: busy,
          onOpen: completed && !busy ? () => _open(task) : null,
          onRemove: busy ? null : () => _remove(task),
          onAction: busy || completed
              ? null
              : () => _perform(
                  task.id,
                  () =>
                      retry ? _service.retry(task.id) : _service.pause(task.id),
                ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('视频缓存'),
          bottom: const TabBar(
            tabs: [
              Tab(text: '缓存中'),
              Tab(text: '已缓存'),
            ],
          ),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Text(
                '缓存位于 Android/data 应用专属目录. 仅在前台下载, 暂停后从头开始.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Expanded(
              child: Obx(() {
                if (!_service.ready.value) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _service.initializationError.value ?? '缓存加载失败或尚未就绪',
                        ),
                        const SizedBox(height: 8),
                        FilledButton(
                          key: const ValueKey('download-initialize'),
                          onPressed: _initializing ? null : _initialize,
                          child: _initializing
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text('重新加载'),
                        ),
                      ],
                    ),
                  );
                }
                final items = _service.items.toList();
                return TabBarView(
                  children: [
                    _list(
                      items
                          .where(
                            (task) => task.status != DownloadStatus.completed,
                          )
                          .toList(),
                      completed: false,
                    ),
                    _list(
                      items
                          .where(
                            (task) => task.status == DownloadStatus.completed,
                          )
                          .toList(),
                      completed: true,
                    ),
                  ],
                );
              }),
            ),
          ],
        ),
      ),
    );
  }
}

class _DownloadTile extends StatelessWidget {
  const _DownloadTile({
    super.key,
    required this.task,
    required this.busy,
    required this.onOpen,
    required this.onRemove,
    required this.onAction,
  });

  final DownloadTask task;
  final bool busy;
  final VoidCallback? onOpen;
  final VoidCallback? onRemove;
  final VoidCallback? onAction;

  String get _status => switch (task.status) {
    DownloadStatus.queued => '排队中',
    DownloadStatus.downloading => '下载中',
    DownloadStatus.paused => '已暂停',
    DownloadStatus.completed => '已缓存',
    DownloadStatus.failed => '下载失败',
  };

  String _bytes(int value) {
    if (value < 1024) return '$value B';
    if (value < 1024 * 1024) return '${(value / 1024).toStringAsFixed(1)} KB';
    if (value < 1024 * 1024 * 1024) {
      return '${(value / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(value / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final completed = task.status == DownloadStatus.completed;
    final retry =
        task.status == DownloadStatus.paused ||
        task.status == DownloadStatus.failed;
    final size = task.total > 0
        ? '${_bytes(task.received)} / ${_bytes(task.total)}'
        : '${_bytes(task.received)} / 大小未知';
    return InkWell(
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'P${task.part + 1} ${task.partTitle}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 6),
                  Text('$_status - $size', style: theme.textTheme.bodySmall),
                  if (!completed) ...[
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: task.status == DownloadStatus.downloading
                          ? task.progress
                          : task.progress ?? 0,
                      minHeight: 3,
                    ),
                  ],
                  if (task.status == DownloadStatus.failed &&
                      task.error != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      task.error!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  if (completed)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text('点击播放本地视频'),
                    )
                  else
                    TextButton(
                      key: ValueKey('download-action-${task.id}'),
                      onPressed: onAction,
                      child: Text(retry ? '从头重试' : '暂停'),
                    ),
                ],
              ),
            ),
            if (busy)
              const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            IconButton(
              key: ValueKey('download-remove-${task.id}'),
              tooltip: '删除缓存',
              onPressed: onRemove,
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
      ),
    );
  }
}
