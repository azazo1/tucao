import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tucao/models/download_task.dart';
import 'package:tucao/services/download/download_service.dart';
import 'package:tucao/utils/logger.dart';

/// 缓存页与缓存队列页共用的操作: 防重, 暂停与继续切换, 删除确认.
mixin DownloadActions<T extends StatefulWidget> on State<T> {
  final downloads = DownloadService.instance;

  /// 正在执行操作的任务或视频, 期间不响应重复点击.
  final busy = <String>{};

  bool get onTop => mounted && ModalRoute.of(context)?.isCurrent == true;

  void notify(String message, {SnackBarAction? action}) {
    if (!onTop) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(message), action: action));
  }

  Future<void> perform(
    String key,
    Future<void> Function() action, {
    String failure = '操作失败, 请稍后重试',
  }) async {
    if (busy.contains(key) || !onTop) {
      return;
    }
    setState(() => busy.add(key));
    try {
      await action();
    } catch (error, stackTrace) {
      Log.e('缓存操作失败 $key', error: error, stackTrace: stackTrace);
      notify(failure);
    } finally {
      if (mounted) {
        setState(() => busy.remove(key));
      }
    }
  }

  /// 点整行: 下载中或排队时暂停, 暂停或失败时继续.
  Future<void> toggle(DownloadTask task) => perform(task.id, () async {
    switch (task.status) {
      case DownloadStatus.downloading:
      case DownloadStatus.queued:
        Log.i('用户暂停缓存 ${task.id}');
        await downloads.pause(task.id);
      case DownloadStatus.paused:
      case DownloadStatus.failed:
        Log.i('用户继续缓存 ${task.id}');
        await downloads.retry(task.id);
      case DownloadStatus.completed:
        break;
    }
  });

  static const _batchKey = 'download-batch';

  /// 标题栏上的全部暂停或全部开始, 没有未完成的任务时不显示.
  Widget batchAction() => Obx(() {
    final pending = downloads.items
        .where((task) => task.status != DownloadStatus.completed)
        .toList();
    if (!downloads.ready.value || pending.isEmpty) {
      return const SizedBox.shrink();
    }
    final running = pending.any(
      (task) =>
          task.status == DownloadStatus.downloading ||
          task.status == DownloadStatus.queued,
    );
    return IconButton(
      key: ValueKey(running ? 'download-pause-all' : 'download-resume-all'),
      tooltip: running ? '全部暂停' : '全部开始',
      onPressed: busy.contains(_batchKey)
          ? null
          : () => perform(_batchKey, () {
              Log.i(running ? '用户暂停全部缓存' : '用户继续全部缓存');
              return running ? downloads.pauseAll() : downloads.resumeAll();
            }),
      icon: Icon(
        running ? Icons.pause_circle_outline : Icons.play_circle_outline,
      ),
    );
  });

  Future<bool> confirmRemove(String content) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除缓存'),
        content: Text(content),
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
    return confirmed == true && onTop;
  }

  Future<void> removeTask(DownloadTask task) => perform(task.id, () async {
    if (!await confirmRemove('将删除 P${task.part + 1} 的缓存任务和本地文件, 确定继续吗?')) {
      return;
    }
    Log.i('用户删除缓存 ${task.id}');
    await downloads.remove(task.id);
    notify('缓存已删除');
  });
}
