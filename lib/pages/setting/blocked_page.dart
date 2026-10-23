import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tucao/common/adaptive.dart';
import 'package:tucao/common/widgets/loading_widget.dart';
import 'package:tucao/common/widgets/video_card.dart';
import 'package:tucao/models/blocked_video.dart';
import 'package:tucao/services/block_service.dart';
import 'package:tucao/utils/date_utils.dart';
import 'package:tucao/utils/logger.dart';

/// 屏蔽管理.
///
/// 列出本机屏蔽过的番剧与视频, 可以逐条解除, 也可以一次清空.
class BlockedVideoPage extends StatelessWidget {
  const BlockedVideoPage({super.key});

  @override
  Widget build(BuildContext context) {
    final service = BlockService.instance;
    return Scaffold(
      appBar: AppBar(
        title: const Text('屏蔽管理'),
        actions: [
          Obx(() {
            final empty = service.list.isEmpty;
            return TextButton(
              onPressed: empty ? null : () => _clearAll(context, service),
              child: const Text('全部解除'),
            );
          }),
        ],
      ),
      body: Obx(() {
        final error = service.loadError.value;
        if (error != null) {
          return ErrorWidgetView(message: error, onRetry: service.reload);
        }
        final items = service.list;
        if (items.isEmpty) {
          return const EmptyWidget(message: '还没有屏蔽任何内容', icon: Icons.block);
        }
        return Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text('屏蔽只保存在本机, 解除后条目会重新出现在列表里'),
            ),
            Expanded(
              child: ListView.separated(
                padding: EdgeInsets.symmetric(
                  horizontal: Adaptive.sidePadding(
                    context,
                    maxWidth: Adaptive.listMaxWidth,
                  ),
                  vertical: 4,
                ),
                itemCount: items.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) => _BlockedRow(
                  item: items[index],
                  onUnblock: () => _unblock(context, service, items[index]),
                ),
              ),
            ),
          ],
        );
      }),
    );
  }

  Future<void> _unblock(
    BuildContext context,
    BlockService service,
    BlockedVideo item,
  ) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await service.unblock(item.hid);
      messenger?.showSnackBar(SnackBar(content: Text('已解除屏蔽 ${item.title}')));
    } catch (error, stackTrace) {
      Log.e('解除本地屏蔽失败', error: error, stackTrace: stackTrace);
      messenger?.showSnackBar(SnackBar(content: Text('解除屏蔽失败: $error')));
    }
  }

  Future<void> _clearAll(BuildContext context, BlockService service) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('全部解除'),
        content: Text('将解除所有 ${service.list.length} 项屏蔽, 确定继续吗?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('解除'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    try {
      await service.clear();
      messenger?.showSnackBar(const SnackBar(content: Text('已解除全部屏蔽')));
    } catch (error, stackTrace) {
      Log.e('清空本地屏蔽失败', error: error, stackTrace: stackTrace);
      messenger?.showSnackBar(SnackBar(content: Text('解除失败: $error')));
    }
  }
}

/// 一条屏蔽记录.
class _BlockedRow extends StatelessWidget {
  const _BlockedRow({required this.item, required this.onUnblock});

  final BlockedVideo item;
  final VoidCallback onUnblock;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final meta = [
      if (item.typeName.isNotEmpty) item.typeName,
      if (item.blockedAt > 0) '屏蔽于 ${DateUtil.full(item.blockedAt)}',
    ].join(' / ');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 108, child: VideoCover(url: item.cover, radius: 6)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    height: 1.35,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (meta.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    meta,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            tooltip: '解除屏蔽',
            onPressed: onUnblock,
            icon: const Icon(Icons.visibility_outlined),
          ),
        ],
      ),
    );
  }
}
