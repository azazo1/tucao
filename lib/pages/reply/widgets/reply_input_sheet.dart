import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tucao/pages/reply/reply_controller.dart';
import 'package:tucao/pages/reply/reply_smiles.dart';
import 'package:tucao/services/image_pick_service.dart';

/// 评论输入弹层.
class ReplyInputSheet extends StatefulWidget {
  const ReplyInputSheet({
    super.key,
    this.replyToName,
    this.onUploadImage,
    this.imageEnabled = true,
  });

  /// 回复目标的名字, 为空表示发顶层评论.
  final String? replyToName;

  /// 上传图评图片, 返回可插进正文的站点片段.
  ///
  /// 为 null 时不显示图片入口. 权限与大小检查由回调实现负责, 失败时抛出
  /// 带可读提示的异常, 这里只负责显示.
  final Future<String> Function(Uint8List bytes, String fileName)?
  onUploadImage;

  /// 当前账号是否有图评权限, 没有时点按钮只给提示, 不打开选择器.
  final bool imageEnabled;

  @override
  State<ReplyInputSheet> createState() => _ReplyInputSheetState();
}

class _ReplyInputSheetState extends State<ReplyInputSheet> {
  final _controller = TextEditingController();

  /// 是否展开站点表情面板.
  bool _showSmiles = false;

  /// 是否正在上传图片.
  bool _uploading = false;

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

  /// 在光标处插入一段文字, 与站点输入框的行为一致.
  void _insertText(String snippet) {
    final value = _controller.value;
    final selection = value.selection;
    final start = selection.isValid ? selection.start : value.text.length;
    final end = selection.isValid ? selection.end : value.text.length;
    final text = value.text.replaceRange(start, end, snippet);
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: start + snippet.length),
    );
  }

  /// 插入表情代码.
  void _insertSmile(String code) => _insertText(code);

  /// 选一张图并上传, 成功后把站点返回的片段插到光标处.
  ///
  /// 与站点网页端一致: 先把图片传上去拿到片段, 用户确认后再连同正文发送,
  /// 因此上传失败不影响已经打好的文字.
  Future<void> _pickImage() async {
    final upload = widget.onUploadImage;
    if (upload == null || _uploading) {
      return;
    }
    if (!widget.imageEnabled) {
      _toast('图评是破会员特权, 需要先开通破会员');
      return;
    }
    PickedImage? picked;
    try {
      picked = await ImagePickService.pick();
    } on PlatformException catch (e) {
      _toast(cleanReplyError(e.message) ?? '打开图片选择器失败');
      return;
    } catch (_) {
      // 平台通道没注册等异常也按选择失败处理, 不要把红屏抛给用户.
      _toast('打开图片选择器失败');
      return;
    }
    if (!mounted || picked == null) {
      return;
    }
    setState(() => _uploading = true);
    try {
      final snippet = await upload(picked.bytes, picked.fileName);
      if (!mounted) {
        return;
      }
      _insertText(snippet);
    } catch (e) {
      _toast(cleanReplyError(e.toString()) ?? '图片上传失败');
    } finally {
      if (mounted) {
        setState(() => _uploading = false);
      }
    }
  }

  void _toast(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
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
                      decoration: const InputDecoration(
                        hintText: '说点什么',
                        // 自带的计数会多占一行, 右侧图标与发送按钮按底边对齐时
                        // 会落到计数那一行上, 与输入框对不齐. 字数上限仍由
                        // maxLength 拦下, 弹幕栏同样不显示计数.
                        counterText: '',
                      ),
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                  if (widget.onUploadImage != null)
                    IconButton(
                      tooltip: '图片',
                      onPressed: _uploading ? null : _pickImage,
                      icon: _uploading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.image_outlined),
                      visualDensity: VisualDensity.compact,
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
                        // 默认的点击热区会把按钮撑到 48 高, 与 40 高的
                        // 输入框和图标按钮对不齐, 这里只保留可见高度.
                        style: FilledButton.styleFrom(
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
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
