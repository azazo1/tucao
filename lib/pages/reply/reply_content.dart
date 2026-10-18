import 'package:tucao/common/constants.dart';

/// 评论正文里的一段, 可能是文字, 也可能是站点表情.
sealed class ReplyContentPart {
  const ReplyContentPart();
}

class ReplyTextPart extends ReplyContentPart {
  const ReplyTextPart(this.text);

  final String text;
}

/// 站点表情, [name] 是方括号里的名字, [url] 是 gif 地址.
class ReplyEmojiPart extends ReplyContentPart {
  const ReplyEmojiPart({required this.name, required this.url});

  final String name;
  final String url;
}

/// 解析后的评论正文.
class ReplyContent {
  const ReplyContent(this.parts);

  final List<ReplyContentPart> parts;

  bool get isEmpty => parts.isEmpty;
}

final _imgTag = RegExp(r'<img\b[^>]*>', caseSensitive: false);
final _srcAttribute = RegExp(
  r'''src\s*=\s*["']?([^"'\s>]+)''',
  caseSensitive: false,
);
final _smilePath = RegExp(
  r'/smilies/([^/?#]+)\.(?:gif|png|jpe?g|webp)',
  caseSensitive: false,
);

/// 站点评论里的表情以图片形式返回, 这里把图片和文字拆开.
///
/// 普通图片暂不内联, 用 `[图片]` 占位; 表情按图片地址识别.
ReplyContent parseReplyContent(String raw) {
  final source = raw.replaceAll(
    RegExp(r'<br\s*/?>', caseSensitive: false),
    '\n',
  );
  final parts = <ReplyContentPart>[];
  final buffer = StringBuffer();
  var cursor = 0;
  for (final match in _imgTag.allMatches(source)) {
    buffer.write(source.substring(cursor, match.start));
    final src = _srcAttribute.firstMatch(match.group(0)!)?.group(1) ?? '';
    final emoji = _emojiOf(src);
    if (emoji != null) {
      _flushText(parts, buffer);
      parts.add(emoji);
    } else if (src.isNotEmpty) {
      buffer.write('[图片]');
    }
    cursor = match.end;
  }
  buffer.write(source.substring(cursor));
  _flushText(parts, buffer);
  _trimEdges(parts);
  return ReplyContent(parts);
}

/// 清洗评论正文, 只保留文字, 表情图片也会被去掉.
///
/// 纯文本场景使用, 需要显示表情时用 [parseReplyContent].
String cleanReplyContent(String raw) {
  final text = raw
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]+>'), '');
  var result = text;
  for (final entry in _entities.entries) {
    result = result.replaceAll(entry.key, entry.value);
  }
  return result.trim();
}

void _flushText(List<ReplyContentPart> parts, StringBuffer buffer) {
  final text = _cleanInline(buffer.toString());
  buffer.clear();
  if (text.isNotEmpty) {
    parts.add(ReplyTextPart(text));
  }
}

String _cleanInline(String raw) {
  var text = raw.replaceAll(RegExp(r'<[^>]+>'), '');
  for (final entry in _entities.entries) {
    text = text.replaceAll(entry.key, entry.value);
  }
  return text;
}

ReplyEmojiPart? _emojiOf(String src) {
  if (src.isEmpty) {
    return null;
  }
  final match = _smilePath.firstMatch(src);
  if (match == null) {
    return null;
  }
  var name = match.group(1)!;
  try {
    name = Uri.decodeComponent(name);
  } on ArgumentError {
    // 保持原始名字, 不影响后续显示.
  }
  return ReplyEmojiPart(name: name, url: _absolute(src));
}

String _absolute(String url) {
  if (url.startsWith('http://') || url.startsWith('https://')) {
    return url;
  }
  return '${Constants.baseUrl}${url.replaceFirst(RegExp(r'^/'), '')}';
}

/// 去掉正文整体首尾的空白, 但不影响表情两侧的文本.
void _trimEdges(List<ReplyContentPart> parts) {
  if (parts.isNotEmpty && parts.first is ReplyTextPart) {
    final text = (parts.first as ReplyTextPart).text.trimLeft();
    if (text.isEmpty) {
      parts.removeAt(0);
    } else {
      parts[0] = ReplyTextPart(text);
    }
  }
  if (parts.isNotEmpty && parts.last is ReplyTextPart) {
    final text = (parts.last as ReplyTextPart).text.trimRight();
    if (text.isEmpty) {
      parts.removeLast();
    } else {
      parts[parts.length - 1] = ReplyTextPart(text);
    }
  }
}

/// `&amp;` 放在最后替换, 避免二次解码.
const _entities = <String, String>{
  '&lt;': '<',
  '&gt;': '>',
  '&quot;': '"',
  '&#39;': "'",
  '&nbsp;': ' ',
  '&amp;': '&',
};
