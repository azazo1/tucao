import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tucao/common/adaptive.dart';
import 'package:tucao/common/widgets/loading_widget.dart';
import 'package:tucao/common/widgets/video_card.dart';
import 'package:tucao/router/routes.dart';
import 'package:tucao/services/block_service.dart';
import 'package:tucao/services/history_service.dart';
import 'package:tucao/utils/date_utils.dart';
import 'package:tucao/utils/logger.dart';
import 'package:tucao/utils/utils.dart';

/// 播放历史页.
///
/// 历史只保存在本地, 数据源是 [HistoryService] 的响应式列表.
class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  final _service = HistoryService.instance;

  void _open(HistoryItem item) {
    Get.toNamed(
      Routes.video,
      parameters: {'hid': item.video.hid, 'part': item.part.toString()},
    );
  }

  Future<void> _remove(HistoryItem item) async {
    await _service.remove(item);
    if (!mounted) {
      return;
    }
    Get.snackbar('已删除', item.video.title, duration: const Duration(seconds: 2));
  }

  Future<void> _block(HistoryItem item) async {
    try {
      await BlockService.instance.block(item.video);
      if (!mounted) {
        return;
      }
      Get.snackbar(
        '已屏蔽',
        item.video.title,
        duration: const Duration(seconds: 2),
      );
    } catch (error, stackTrace) {
      Log.e('屏蔽播放历史条目失败', error: error, stackTrace: stackTrace);
      if (mounted) {
        Get.snackbar('屏蔽失败', '$error');
      }
    }
  }

  /// 长按弹出的操作菜单.
  Future<void> _showMenu(HistoryItem item) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.play_arrow_outlined),
              title: const Text('继续播放'),
              onTap: () {
                Navigator.pop(sheetContext);
                _open(item);
              },
            ),
            ListTile(
              leading: const Icon(Icons.block),
              title: const Text('屏蔽此内容'),
              subtitle: const Text('不再出现在本地列表里'),
              onTap: () {
                Navigator.pop(sheetContext);
                _block(item);
              },
            ),
            ListTile(
              leading: Icon(
                Icons.delete_outline,
                color: Theme.of(sheetContext).colorScheme.error,
              ),
              title: Text(
                '删除这条记录',
                style: TextStyle(
                  color: Theme.of(sheetContext).colorScheme.error,
                ),
              ),
              onTap: () {
                Navigator.pop(sheetContext);
                _remove(item);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _clear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('清空播放历史'),
        content: const Text('将删除全部本地播放记录, 确定继续吗?'),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Get.back(result: true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    await _service.clear();
    if (!mounted) {
      return;
    }
    Get.snackbar('已清空', '本地播放历史已删除');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('播放历史'),
        actions: [
          Obx(() {
            final empty = _service.list.isEmpty;
            return TextButton(
              onPressed: empty ? null : _clear,
              child: const Text('清空'),
            );
          }),
        ],
      ),
      body: Obx(() {
        final all = _service.list;
        final list = all
            .where(
              (item) => !BlockService.instance.isBlocked(item.video.hid),
            )
            .toList();
        if (all.isEmpty) {
          return const EmptyWidget(message: '还没有播放记录', icon: Icons.history);
        }
        if (list.isEmpty) {
          return const EmptyWidget(
            message: '播放记录都已被屏蔽',
            icon: Icons.block,
          );
        }
        return ListView.separated(
          padding: EdgeInsets.symmetric(
            horizontal: Adaptive.sidePadding(
              context,
              maxWidth: Adaptive.listMaxWidth,
            ),
            vertical: 4,
          ),
          itemCount: list.length,
          separatorBuilder: (context, index) =>
              const Divider(height: 1, indent: 158),
          itemBuilder: (context, index) {
            final item = list[index];
            return Dismissible(
              key: ValueKey('${item.video.hid}_${item.part}'),
              direction: DismissDirection.endToStart,
              background: const _DeleteBackground(),
              onDismissed: (direction) => _remove(item),
              child: _HistoryTile(
                item: item,
                onTap: () => _open(item),
                onLongPress: () => _showMenu(item),
              ),
            );
          },
        );
      }),
    );
  }
}

/// 左滑时露出的删除底色.
class _DeleteBackground extends StatelessWidget {
  const _DeleteBackground();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.errorContainer,
      child: Align(
        alignment: Alignment.centerRight,
        child: Padding(
          padding: const EdgeInsets.only(right: 20),
          child: Icon(Icons.delete_outline, color: scheme.onErrorContainer),
        ),
      ),
    );
  }
}

/// 单条播放记录.
class _HistoryTile extends StatelessWidget {
  const _HistoryTile({
    required this.item,
    required this.onTap,
    required this.onLongPress,
  });

  final HistoryItem item;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final video = item.video;
    final watched = Utils.formatSeconds(item.progress);
    final total = Utils.formatSeconds(item.duration);
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 148,
              child: VideoCover(
                url: video.cover,
                overlay: CoverBadge(text: '${(item.percent * 100).round()}%'),
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
                  const SizedBox(height: 6),
                  if (video.partCount > 1)
                    Text(
                      'P${item.part + 1}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  const SizedBox(height: 2),
                  Text(
                    '已看 $watched / $total',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: item.percent,
                      minHeight: 3,
                      backgroundColor: scheme.surfaceContainerHighest,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    DateUtil.relative(item.updateTime ~/ 1000),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
