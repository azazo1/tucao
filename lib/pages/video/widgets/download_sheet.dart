import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tucao/models/download_task.dart';
import 'package:tucao/models/video.dart';
import 'package:tucao/services/download/download_service.dart';
import 'package:tucao/utils/logger.dart';

/// 选择可下载的分 P, 只提交前台缓存队列, 不将提交当作缓存完成.
Future<void> showVideoDownloadSheet(
  BuildContext context, {
  required VideoModel video,
  required int initialPart,
}) async {
  if (!context.mounted || ModalRoute.of(context)?.isCurrent != true) {
    return;
  }
  final route = ModalRoute.of(context);
  final result = await showModalBottomSheet<_DownloadSubmission>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => _VideoDownloadSheet(
      video: video,
      initialPart: initialPart,
    ),
  );
  if (result == null || !context.mounted || route?.isCurrent != true) {
    return;
  }
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text('已提交 ${result.succeeded} 项, 失败 ${result.failed} 项. 提交不代表缓存完成.'),
  ));
}

class _DownloadSubmission {
  const _DownloadSubmission(this.succeeded, this.failed);

  final int succeeded;
  final int failed;
}

class _VideoDownloadSheet extends StatefulWidget {
  const _VideoDownloadSheet({required this.video, required this.initialPart});

  final VideoModel video;
  final int initialPart;

  @override
  State<_VideoDownloadSheet> createState() => _VideoDownloadSheetState();
}

class _VideoDownloadSheetState extends State<_VideoDownloadSheet> {
  final _service = DownloadService.instance;
  final _selected = <int>{};
  bool _submitting = false;

  bool get _current => mounted && ModalRoute.of(context)?.isCurrent == true;

  @override
  void initState() {
    super.initState();
    final part = widget.initialPart;
    if (part >= 0 && part < widget.video.parts.length &&
        _reason(part, _service.items.toList(), ready: _service.ready.value) == null) {
      _selected.add(part);
    }
  }

  DownloadTask? _existing(int part, List<DownloadTask> tasks) {
    final id = '${widget.video.hid}-$part';
    for (final task in tasks) {
      if (task.id == id) return task;
    }
    return null;
  }

  String? _reason(int part, List<DownloadTask> tasks, {required bool ready}) {
    final source = widget.video.parts[part].file?.trim() ?? '';
    if (source.isEmpty) return '没有可下载的直链';
    final uri = DownloadTask.sourceUri(source);
    if (uri == null) return '下载链接无效, 仅支持 HTTP 或 HTTPS';
    if (uri.path.toLowerCase().endsWith('.m3u8')) {
      return '暂不支持 m3u8 分段媒体缓存';
    }
    if (!DownloadTask.validIdentity(widget.video.hid, part)) {
      return '视频编号无效';
    }
    final task = _existing(part, tasks);
    switch (task?.status) {
      case DownloadStatus.queued:
        return '已在缓存队列中';
      case DownloadStatus.downloading:
        return '正在下载';
      case DownloadStatus.completed:
        return '已缓存';
      default:
        break;
    }
    if (!ready) return '缓存服务尚未就绪';
    return null;
  }

  Future<void> _submit() async {
    if (_submitting || !_current || !_service.ready.value) {
      return;
    }
    final parts = _selected.where((part) => _reason(
      part, _service.items.toList(), ready: _service.ready.value,
    ) == null).toList()..sort();
    if (parts.isEmpty) return;
    setState(() => _submitting = true);
    var succeeded = 0;
    var failed = 0;
    try {
      for (final part in parts) {
        // 关闭弹层或进入其他路由后, 不再提交余下分 P.
        if (!_current) return;
        if (_reason(part, _service.items.toList(), ready: _service.ready.value) != null) {
          failed++;
          continue;
        }
        try {
          await _service.enqueue(widget.video, part);
          succeeded++;
        } catch (error, stackTrace) {
          failed++;
          Log.e('提交视频缓存失败', error: error, stackTrace: stackTrace);
        }
      }
      if (mounted && _current) {
        Navigator.of(context).pop(_DownloadSubmission(succeeded, failed));
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.72,
        child: Obx(() {
          final ready = _service.ready.value;
          final tasks = _service.items.toList();
          final selected = _selected.where((part) => _reason(part, tasks, ready: ready) == null).toSet();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text('选择缓存分 P', style: theme.textTheme.titleMedium),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  '仅在前台下载. 暂停或失败后, 重试将从头开始.',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
              if (!ready)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Text('缓存服务不可用, 请在视频缓存页面重新加载.',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
                ),
              const SizedBox(height: 8),
              Expanded(
                child: widget.video.parts.isEmpty
                    ? const Center(child: Text('没有可缓存的分 P'))
                    : ListView.builder(
                        itemCount: widget.video.parts.length,
                        itemBuilder: (context, part) {
                          final reason = _reason(part, tasks, ready: ready);
                          final existing = _existing(part, tasks);
                          final retry = existing?.status == DownloadStatus.paused ||
                              existing?.status == DownloadStatus.failed;
                          return CheckboxListTile(
                            key: ValueKey('download-part-$part'),
                            controlAffinity: ListTileControlAffinity.leading,
                            title: Text('P${part + 1} ${widget.video.parts[part].title}'),
                            subtitle: reason != null
                                ? Text(reason)
                                : retry ? const Text('从头重试') : null,
                            value: selected.contains(part),
                            onChanged: reason != null || _submitting ? null : (value) {
                              setState(() {
                                if (value == true) {
                                  _selected.add(part);
                                } else {
                                  _selected.remove(part);
                                }
                              });
                            },
                          );
                        },
                      ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton(
                  key: const ValueKey('download-submit'),
                  onPressed: _submitting || selected.isEmpty || !ready ? null : _submit,
                  child: _submitting
                      ? const SizedBox(width: 20, height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : Text('开始缓存 (${selected.length})'),
                ),
              ),
            ],
          );
        }),
      ),
    );
  }
}
