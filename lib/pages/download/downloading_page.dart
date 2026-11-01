import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tucao/common/adaptive.dart';
import 'package:tucao/models/download_task.dart';
import 'package:tucao/pages/download/download_actions.dart';
import 'package:tucao/pages/download/widgets/download_task_tile.dart';

/// 全部缓存中任务, 从离线缓存页的 "全部" 进入.
class DownloadingPage extends StatefulWidget {
  const DownloadingPage({super.key});

  @override
  State<DownloadingPage> createState() => _DownloadingPageState();
}

class _DownloadingPageState extends State<DownloadingPage>
    with DownloadActions {
  @override
  Widget build(BuildContext context) {
    final side = Adaptive.sidePadding(context);
    return Scaffold(
      appBar: AppBar(title: const Text('正在缓存'), actions: [batchAction()]),
      body: Obx(() {
        final pending = downloads.items
            .where((task) => task.status != DownloadStatus.completed)
            .toList();
        if (pending.isEmpty) {
          return const Center(child: Text('全部缓存已完成'));
        }
        return ListView.builder(
          padding: EdgeInsets.fromLTRB(side, 4, side, 24),
          itemCount: pending.length,
          itemBuilder: (context, index) {
            final task = pending[index];
            return DownloadTaskTile(
              key: ValueKey(task.id),
              task: task,
              busy: busy.contains(task.id),
              onToggle: () => unawaited(toggle(task)),
              onRemove: () => unawaited(removeTask(task)),
            );
          },
        );
      }),
    );
  }
}
