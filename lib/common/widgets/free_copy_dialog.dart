import 'package:flutter/material.dart';

/// 纯文本内容的自由复制弹窗.
///
/// 弹窗里的文字可以拖选, 使用系统的选择菜单复制.
Future<void> showFreeCopyTextDialog(
  BuildContext context, {
  required String text,
  String title = '自由复制',
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380, maxHeight: 480),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(dialogContext).textTheme.titleSmall),
              const SizedBox(height: 10),
              Flexible(
                child: SingleChildScrollView(
                  child: SelectionArea(
                    child: Text(
                      text,
                      style: Theme.of(dialogContext).textTheme.bodyMedium
                          ?.copyWith(height: 1.6),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
