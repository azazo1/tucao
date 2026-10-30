import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:tucao/models/reply.dart';
import 'package:tucao/pages/reply/reply_content.dart';
import 'package:tucao/pages/reply/widgets/comment_image.dart';

/// 评论的自由复制弹窗.
///
/// 弹窗里的正文可以拖选复制. 有表情或图片评时, 右上角可以切换成文本,
/// 这时表情显示为 [名字], 图片显示为 Markdown 链接, 方便一起选中复制.
Future<void> showReplyCopyDialog(BuildContext context, ReplyModel comment) {
  return showDialog<void>(
    context: context,
    builder: (_) =>
        _ReplyCopyDialog(content: parseReplyContent(comment.content)),
  );
}

class _ReplyCopyDialog extends StatefulWidget {
  const _ReplyCopyDialog({required this.content});

  final ReplyContent content;

  @override
  State<_ReplyCopyDialog> createState() => _ReplyCopyDialogState();
}

class _ReplyCopyDialogState extends State<_ReplyCopyDialog> {
  /// 是否把表情与图片显示成图片, 关掉后显示可复制的文本.
  bool _showEmote = true;

  bool get _hasMedia => widget.content.parts.any(
    (part) => part is ReplyEmojiPart || part is ReplyImagePart,
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final style = theme.textTheme.bodyMedium?.copyWith(
      height: 1.7,
      color: scheme.onSurface,
    );
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380, maxHeight: 480),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('自由复制', style: theme.textTheme.titleSmall),
                  const Spacer(),
                  if (_hasMedia)
                    TextButton(
                      onPressed: () => setState(() => _showEmote = !_showEmote),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                      child: Text(_showEmote ? '文本' : '表情'),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Flexible(
                child: SingleChildScrollView(
                  child: SelectionArea(
                    child: Text.rich(
                      TextSpan(children: _buildSpans()),
                      style: style,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<InlineSpan> _buildSpans() {
    final spans = <InlineSpan>[];
    for (final part in widget.content.parts) {
      switch (part) {
        case ReplyTextPart(:final text):
          spans.add(TextSpan(text: text));
        case ReplyEmojiPart(:final name, :final url):
          spans.add(_buildEmoji(name, url));
        case ReplyImagePart(:final url):
          spans.add(_buildImage(url));
      }
    }
    return spans;
  }

  InlineSpan _buildEmoji(String name, String url) {
    if (!_showEmote) {
      return TextSpan(text: '[$name]');
    }
    return WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 1),
        child: CachedNetworkImage(
          imageUrl: url,
          width: 20,
          height: 20,
          fit: BoxFit.contain,
          errorWidget: (context, url, error) => Text('[$name]'),
        ),
      ),
    );
  }

  InlineSpan _buildImage(String url) {
    if (!_showEmote) {
      return TextSpan(text: '![图片]($url)');
    }
    return WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: CommentImage(url: url, height: 96),
    );
  }
}
