import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tucao/models/update_download.dart';
import 'package:tucao/services/update/update_download_service.dart';
import 'package:tucao/services/update/update_installer.dart';
import 'package:tucao/utils/logger.dart';

/// 关于对话框里的更新包下载状态与操作.
///
/// 下载在对话框之外的服务里进行, 这里只展示当前进度并转发操作,
/// 因此关掉对话框不会打断下载, 重新打开后接着显示.
class UpdateDownloadPanel extends StatefulWidget {
  const UpdateDownloadPanel({super.key, required this.service});

  final UpdateDownloadService service;

  @override
  State<UpdateDownloadPanel> createState() => _UpdateDownloadPanelState();
}

class _UpdateDownloadPanelState extends State<UpdateDownloadPanel> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final noteStyle = TextStyle(
      fontSize: 12,
      height: 1.5,
      color: scheme.onSurfaceVariant,
    );
    return Obx(() {
      final current = widget.service.state.value;
      if (!current.hasTask) {
        return const SizedBox.shrink();
      }
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (current.isDownloading) ...[
              LinearProgressIndicator(value: current.progress),
              const SizedBox(height: 6),
              Text(_progressText(current), style: noteStyle),
            ] else if (current.status == UpdateDownloadStatus.ready)
              Text(
                '安装包已下载好, 安装由系统安装器完成, 覆盖安装即可.',
                style: noteStyle,
              )
            else if (current.error != null)
              Text(current.error!, style: noteStyle),
            const SizedBox(height: 8),
            Row(children: _actions(current)),
          ],
        ),
      );
    });
  }

  List<Widget> _actions(UpdateDownloadState current) {
    switch (current.status) {
      case UpdateDownloadStatus.downloading:
        return [
          TextButton(
            onPressed: _busy ? null : () => _perform(widget.service.pause),
            child: const Text('取消下载'),
          ),
        ];
      case UpdateDownloadStatus.ready:
        return [
          TextButton(
            onPressed: _busy ? null : () => _perform(widget.service.discard),
            child: const Text('删除安装包'),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: _busy ? null : () => _perform(_install),
            child: const Text('安装'),
          ),
        ];
      case UpdateDownloadStatus.paused:
      case UpdateDownloadStatus.failed:
        return [
          TextButton(
            onPressed: _busy ? null : () => _perform(widget.service.discard),
            child: const Text('取消'),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: _busy ? null : _restart,
            child: const Text('重新下载'),
          ),
        ];
      case UpdateDownloadStatus.idle:
        return const [];
    }
  }

  String _progressText(UpdateDownloadState current) {
    final received = _bytesText(current.received);
    final total = current.total > 0 ? _bytesText(current.total) : '大小未知';
    final progress = current.progress;
    final percent = progress == null ? '' : ' ${(progress * 100).round()}%';
    return '正在下载$percent ($received / $total)';
  }

  static String _bytesText(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    }
    final megabytes = bytes / (1024 * 1024);
    if (megabytes >= 1) {
      return '${megabytes.toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }

  Future<void> _install() async {
    final outcome = await widget.service.install();
    if (outcome == UpdateInstallOutcome.permissionRequired) {
      await _askPermission();
      return;
    }
    _notify(switch (outcome) {
      UpdateInstallOutcome.started => '已交给系统安装器, 按系统提示完成安装',
      UpdateInstallOutcome.missing => '安装包已不在本地, 请重新下载',
      UpdateInstallOutcome.failed => '无法打开系统安装器, 请稍后重试',
      UpdateInstallOutcome.permissionRequired => '',
    });
  }

  /// 系统要求逐个应用放行安装来源, 这里先问一句再跳设置.
  Future<void> _askPermission() async {
    if (!mounted) {
      return;
    }
    final open = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('需要安装权限'),
        content: const Text(
          '系统要求先允许本应用安装未知应用, 才能打开安装器. 现在去设置里放行吗?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('暂不'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('去设置'),
          ),
        ],
      ),
    );
    if (open != true) {
      return;
    }
    if (!await UpdateInstaller.openInstallSettings()) {
      _notify('没能打开设置页, 请在系统设置里允许本应用安装未知应用');
    }
  }

  /// 重新开始下载.
  ///
  /// 不放进 [_perform]: 服务的 retry 要陪跑整个下载, 等它的话 _busy 会一直
  /// 是真, 刚点出来的"取消下载"跟着被禁用, 用户就中断不了这一次下载了.
  /// 意外抛出的异常在这里兜住, 服务内部的失败已经写进状态.
  void _restart() {
    unawaited(
      widget.service.retry().catchError((Object error, StackTrace stackTrace) {
        Log.e('重新下载更新包失败', error: error, stackTrace: stackTrace);
        _notify('操作失败, 请稍后重试');
      }),
    );
  }

  Future<void> _perform(Future<void> Function() action) async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      await action();
    } catch (error, stackTrace) {
      Log.e('更新包操作失败', error: error, stackTrace: stackTrace);
      _notify('操作失败, 请稍后重试');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _notify(String message) {
    if (!mounted || message.isEmpty) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}
