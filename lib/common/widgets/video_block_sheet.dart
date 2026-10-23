import 'package:flutter/material.dart';
import 'package:tucao/models/video.dart';
import 'package:tucao/services/block_service.dart';
import 'package:tucao/utils/logger.dart';

/// 视频条目的屏蔽操作, 长按卡片或从播放页菜单打开.
///
/// 屏蔽只写入本地记录, 不请求站点; 已经屏蔽时这里提供解除入口,
/// 用于播放页这类仍然能打开已屏蔽条目的场景.
Future<void> showVideoBlockSheet(BuildContext context, VideoModel video) async {
  final service = BlockService.instance;
  final blocked = service.isBlocked(video.hid);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final action = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              video.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(sheetContext).textTheme.titleSmall,
            ),
          ),
          ListTile(
            leading: Icon(
              blocked ? Icons.visibility_outlined : Icons.block,
              color: blocked ? null : Theme.of(sheetContext).colorScheme.error,
            ),
            title: Text(blocked ? '取消屏蔽' : '屏蔽此内容'),
            subtitle: Text(blocked ? '恢复在本地列表里显示' : '不再出现在首页, 番组, 搜索与排行等列表'),
            onTap: () => Navigator.pop(sheetContext, true),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (action != true) {
    return;
  }
  try {
    if (blocked) {
      await service.unblock(video.hid);
      messenger?.showSnackBar(SnackBar(content: Text('已取消屏蔽 ${video.title}')));
    } else {
      await service.block(video);
      messenger?.showSnackBar(
        SnackBar(content: Text('已屏蔽 ${video.title}, 可在设置 - 屏蔽管理里恢复')),
      );
    }
  } catch (error, stackTrace) {
    Log.e('更新本地屏蔽失败', error: error, stackTrace: stackTrace);
    messenger?.showSnackBar(SnackBar(content: Text('屏蔽操作失败: $error')));
  }
}
