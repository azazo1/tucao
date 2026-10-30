import 'package:tucao/models/reply.dart';
import 'package:tucao/pages/reply/reply_content.dart';

/// 把评论正文转换成用于复制的纯文本.
///
/// 文字保持不变, 站点表情写成 [名字], 评论图片写成 Markdown 图片语法,
/// 每张图片单独占一行. 楼中楼也只转换正文, 不加回复对象前缀.
String replyCopyText(ReplyModel comment) {
  final content = parseReplyContent(comment.content);
  final buffer = _CopyTextBuffer();
  for (final part in content.parts) {
    switch (part) {
      case ReplyTextPart(:final text):
        buffer.write(text);
      case ReplyEmojiPart(:final name):
        buffer.write('[$name]');
      case ReplyImagePart(:final url):
        buffer.writeLine('![图片]($url)');
    }
  }
  return buffer.build();
}

/// 写文本时维护末尾换行状态, 让图片单独成行又不产生多余空行.
class _CopyTextBuffer {
  final _buffer = StringBuffer();

  bool _endsWithNewline = true;

  void write(String text) {
    if (text.isEmpty) {
      return;
    }
    _buffer.write(text);
    _endsWithNewline = text.endsWith('\n');
  }

  void writeLine(String text) {
    if (!_endsWithNewline) {
      _buffer.write('\n');
    }
    _buffer.write(text);
    _buffer.write('\n');
    _endsWithNewline = true;
  }

  String build() => _buffer.toString().trim();
}
