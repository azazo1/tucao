import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tucao/models/danmaku_send_style.dart';
import 'package:tucao/pages/video/widgets/danmaku_style_picker.dart';

/// 全屏时的弹幕输入框, 从底部弹出.
///
/// [onSend] 返回错误文本, 为空表示发送成功. 失败时框内直接给出原因,
/// 不额外弹提示打断画面. 调色板按钮收起键盘, 在框上方展开 [style] 的选择.
Future<void> showDanmakuInputSheet(
  BuildContext context, {
  required Future<String?> Function(String text) onSend,
  required Rx<DanmakuSendStyle> style,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.black.withValues(alpha: 0.85),
    barrierColor: Colors.transparent,
    builder: (context) => _DanmakuInput(onSend: onSend, style: style),
  );
}

class _DanmakuInput extends StatefulWidget {
  const _DanmakuInput({required this.onSend, required this.style});

  final Future<String?> Function(String text) onSend;
  final Rx<DanmakuSendStyle> style;

  @override
  State<_DanmakuInput> createState() => _DanmakuInputState();
}

class _DanmakuInputState extends State<_DanmakuInput> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  bool _sending = false;
  bool _picking = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // 点回输入框时收起样式选择, 让键盘回来.
    _focus.addListener(() {
      if (_focus.hasFocus && _picking) {
        setState(() => _picking = false);
      }
    });
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _togglePicker() {
    if (_picking) {
      setState(() => _picking = false);
      _focus.requestFocus();
      return;
    }
    _focus.unfocus();
    setState(() => _picking = true);
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        10,
        12,
        10 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_picking)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                // 面板背景是深色, 选择器按深色主题绘制才看得清.
                child: Theme(
                  data: theme.copyWith(
                    colorScheme: ColorScheme.fromSeed(
                      seedColor: scheme.primary,
                      brightness: Brightness.dark,
                    ),
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Obx(
                      () => DanmakuStylePicker(
                        value: widget.style.value,
                        onChanged: (value) => widget.style.value = value,
                      ),
                    ),
                  ),
                ),
              ),
            Row(
              children: [
                IconButton(
                  onPressed: _togglePicker,
                  tooltip: '弹幕样式',
                  isSelected: _picking,
                  icon: const Icon(Icons.palette_outlined, color: Colors.white),
                  selectedIcon: Icon(Icons.palette, color: scheme.primary),
                ),
                Expanded(
                  child: TextField(
                    controller: _text,
                    focusNode: _focus,
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
          ],
        ),
      ),
    );
  }
}
