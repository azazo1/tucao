import 'package:flutter/material.dart';

/// 长按内容后可以选择的复制方式.
enum ContentCopyAction { copyAll, freeCopy }

/// 底部复制菜单: 复制全部与自由复制.
///
/// 调用方拿到返回的动作后自行复制或打开自由复制弹窗.
Future<ContentCopyAction?> showContentCopyMenu(BuildContext context) {
  return showModalBottomSheet<ContentCopyAction>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            leading: const Icon(Icons.copy_all_outlined),
            title: const Text('复制全部'),
            subtitle: const Text('复制整段正文'),
            onTap: () => Navigator.pop(sheetContext, ContentCopyAction.copyAll),
          ),
          ListTile(
            leading: const Icon(Icons.copy_outlined),
            title: const Text('自由复制'),
            subtitle: const Text('选择要复制的文字'),
            onTap: () =>
                Navigator.pop(sheetContext, ContentCopyAction.freeCopy),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}
