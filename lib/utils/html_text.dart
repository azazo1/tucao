import 'package:html/parser.dart' as html_parser;

/// HTML 文本里可能出现的实体, 用于判断是否还需要再解一层.
final _entityPattern = RegExp(
  r'&(?:#\d+|#x[0-9a-fA-F]+|[a-zA-Z][a-zA-Z0-9]+);',
);

/// 把站点返回的富文本还原成可以直接显示的纯文本.
///
/// 简介等字段里会直接带 `&mdash;` 这类 HTML 实体, 偶尔还有 `<br>`,
/// 先用 html 解析器解一层. 个别字段被二次转义 (例如 `&amp;acute;`),
/// 解析后仍残留实体时再补一层, 避免把实体当成正文显示.
String decodeHtmlText(String raw) {
  if (raw.isEmpty) {
    return raw;
  }
  final text = html_parser
      .parseFragment(
        raw.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n'),
      )
      .text;
  if (!_entityPattern.hasMatch(text)) {
    return text;
  }
  return html_parser.parseFragment(text).text;
}
