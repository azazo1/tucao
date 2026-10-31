import 'package:flutter/material.dart';

/// 全屏时的弹幕输入框, 从底部弹出, 键盘收起后自动关闭.
///
/// [onSend] 返回错误文本, 为空表示发送成功. 失败时框内直接给出原因,
/// 不额外弹提示打断画面.
Future<void> showDanmakuInputSheet(
  BuildContext context, {
  required Future<String?> Function(String text) onSend,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.black.withValues(alpha: 0.85),
    barrierColor: Colors.transparent,
    builder: (context) => _DanmakuInput(onSend: onSend),
  );
}

class _DanmakuInput extends StatefulWidget {
  const _DanmakuInput({required this.onSend});

  final Future<String?> Function(String text) onSend;

  @override
  State<_DanmakuInput> createState() => _DanmakuInputState();
}

class _DanmakuInputState extends State<_DanmakuInput> {
  final _text = TextEditingController();
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _text.text;
    if (text.trim().isEmpty || _sending) {
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    final error = await widget.onSend(text);
    if (!mounted) {
      return;
    }
    if (error == null) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _sending = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        10,
        12,
        10 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _text,
                autofocus: true,
                maxLength: 60,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                style: const TextStyle(color: Colors.white, fontSize: 14),
                cursorColor: scheme.primary,
                decoration: InputDecoration(
                  isDense: true,
                  counterText: '',
                  hintText: '发个弹幕见证当下',
                  hintStyle: const TextStyle(color: Colors.white54),
                  errorText: _error,
                  filled: true,
                  fillColor: Colors.white12,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: _sending ? null : _send,
              tooltip: '发送',
              icon: _sending
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send, size: 18),
            ),
          ],
        ),
      ),
    );
  }
}
