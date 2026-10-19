import 'package:flutter/material.dart';

/// 条目上的未读胶囊.
///
/// 站点在未读的条目上用描边胶囊标注, 这里与它保持一致. [text] 由调用方给:
/// 系统公告写的是 "未读", 私信里除 "未读" 之外站点还会写 "对方未读",
/// 那是自己发出去的消息对方还没看, 文本照站点给的显示.
class UnreadBadge extends StatelessWidget {
  const UnreadBadge({super.key, this.text = '未读'});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        border: Border.all(color: scheme.primary),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(color: scheme.primary),
      ),
    );
  }
}
