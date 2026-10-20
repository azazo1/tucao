import 'package:flutter/material.dart';
import 'package:tucao/http/message_http.dart';
import 'package:tucao/utils/logger.dart';

/// 从他人主页发起私信的弹层.
///
/// 站点发送私信必须带上标题, 但这里只让用户写正文: 第一封私信的标题统一用
/// [defaultSubject], 会话标题对收件人而言只是列表里的一行字, 不需要用户再想
/// 一个标题. 已有的会话里回复走消息页, 标题由那边生成.
class PrivateMessageSheet extends StatefulWidget {
  const PrivateMessageSheet({
    super.key,
    required this.toUserName,
    this.displayName = '',
  });

  /// 收件人的站点用户名, 不是 uid.
  ///
  /// 站点私信接口的 info[send_to_id] 实际按 member.username 查收件人.
  final String toUserName;

  /// 收件人昵称, 只用于标题展示, 可以为空.
  final String displayName;

  /// 第一封私信的标题.
  static const defaultSubject = '你好';

  @override
  State<PrivateMessageSheet> createState() => _PrivateMessageSheetState();
}

class _PrivateMessageSheetState extends State<PrivateMessageSheet> {
  final _controller = TextEditingController();

  /// 正在提交, 防止连点发出两条.
  bool _sending = false;

  /// 站点给的失败提示, 留在弹层里显示, 不关掉弹层.
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) {
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    var sent = false;
    try {
      final result = await MessageHttp.send(
        toUserName: widget.toUserName,
        subject: PrivateMessageSheet.defaultSubject,
        content: text,
      );
      if (!mounted) {
        return;
      }
      if (result != null) {
        setState(() => _error = result);
        return;
      }
      sent = true;
      Navigator.of(context).pop(true);
    } catch (e, stackTrace) {
      Log.e('发送私信失败', error: e, stackTrace: stackTrace);
      if (mounted) {
        setState(() => _error = '发送失败, 请稍后重试');
      }
    } finally {
      // 已经关掉弹层时不再更新状态.
      if (mounted && !sent) {
        setState(() => _sending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final name = widget.displayName.trim();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                name.isEmpty ? '发私信' : '给 $name 发私信',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '消息会发送到对方的收件箱, 不会公开显示',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _controller,
                autofocus: true,
                minLines: 3,
                maxLines: 6,
                maxLength: 500,
                textInputAction: TextInputAction.newline,
                decoration: const InputDecoration(
                  hintText: '输入私信内容',
                  border: OutlineInputBorder(),
                  counterText: '',
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 6),
                Text(
                  _error!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.error,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _sending
                        ? null
                        : () => Navigator.of(context).pop(false),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _sending ? null : _submit,
                    child: _sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('发送'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
