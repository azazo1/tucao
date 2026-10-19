import 'package:tucao/utils/html_text.dart';
import 'package:tucao/utils/site_url.dart';

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

/// 评论里贴的图片, [url] 已经补成绝对地址.
class ReplyImagePart extends ReplyContentPart {
  const ReplyImagePart(this.url);

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

/// 站点评论里的表情与图片都以图片形式返回, 这里把它们和文字拆开.
///
/// 表情按图片地址识别, 其余图片交给界面内联显示. 文字部分交给
/// [decodeHtmlText] 处理, 站点偶尔会把整条评论写成 HTML 实体.
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
      _flushText(parts, buffer);
      parts.add(ReplyImagePart(absoluteSiteUrl(src)));
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
String cleanReplyContent(String raw) => decodeHtmlText(raw).trim();

void _flushText(List<ReplyContentPart> parts, StringBuffer buffer) {
  final text = decodeHtmlText(buffer.toString());
  buffer.clear();
  if (text.isNotEmpty) {
    parts.add(ReplyTextPart(text));
  }
}

ReplyEmojiPart? _emojiOf(String src) {
  if (src.isEmpty) {
    return null;
  }
  final url = absoluteSiteUrl(src);
  // 站外地址一律不当表情, 否则别人的评论能让本机自动请求外部主机.
  if (!isSiteImage(url)) {
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
  return ReplyEmojiPart(name: name, url: url);
}

/// 去掉正文整体首尾的空白, 但不影响表情与图片两侧的文本.
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
