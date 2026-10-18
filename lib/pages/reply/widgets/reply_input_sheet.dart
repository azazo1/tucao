import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:tucao/pages/reply/reply_smiles.dart';

/// 评论输入弹层.
class ReplyInputSheet extends StatefulWidget {
  const ReplyInputSheet({super.key, this.replyToName});

  /// 回复目标的名字, 为空表示发顶层评论.
  final String? replyToName;

  @override
  State<ReplyInputSheet> createState() => _ReplyInputSheetState();
}

class _ReplyInputSheetState extends State<ReplyInputSheet> {
  final _controller = TextEditingController();

  /// 是否展开站点表情面板.
  bool _showSmiles = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      return;
    }
    Navigator.of(context).pop(text);
  }

  /// 在光标处插入表情代码, 与站点输入框的行为一致.
  void _insertSmile(String code) {
    final value = _controller.value;
    final selection = value.selection;
    final start = selection.isValid ? selection.start : value.text.length;
    final end = selection.isValid ? selection.end : value.text.length;
    final text = value.text.replaceRange(start, end, code);
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: start + code.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final target = widget.replyToName;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (target != null && target.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Icon(
                        Icons.reply,
                        size: 15,
                        color: scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          '回复 @$target',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      autofocus: true,
                      minLines: 1,
                      maxLines: 4,
                      maxLength: 500,
                      textInputAction: TextInputAction.newline,
                      decoration: InputDecoration(
                        hintText: '说点什么',
                        counterStyle: TextStyle(
                          fontSize: 11,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                  IconButton(
                    tooltip: _showSmiles ? '收起表情' : '表情',
                    onPressed: () =>
                        setState(() => _showSmiles = !_showSmiles),
                    icon: Icon(
                      _showSmiles
                          ? Icons.keyboard_outlined
                          : Icons.emoji_emotions_outlined,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                  const SizedBox(width: 4),
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _controller,
                    builder: (context, value, child) {
                      final canSend = value.text.trim().isNotEmpty;
                      return FilledButton(
                        onPressed: canSend ? _submit : null,
                        child: const Text('发送'),
                      );
                    },
                  ),
                ],
              ),
              if (_showSmiles) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final smile in replySmiles)
                      Tooltip(
                        message: smile.code,
                        child: InkWell(
                          onTap: () => _insertSmile(smile.code),
                          borderRadius: BorderRadius.circular(4),
                          child: Padding(
                            padding: const EdgeInsets.all(2),
                            child: CachedNetworkImage(
                              imageUrl: smile.url,
                              width: 24,
                              height: 24,
                              fit: BoxFit.contain,
                              errorWidget: (context, url, error) => Text(
                                smile.code,
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
