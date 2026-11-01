import 'dart:convert' show utf8;
import 'dart:ui' show Color, TextAlign;

import 'package:html/dom.dart';
import 'package:tucao/common/rich_html/rich_content.dart';
import 'package:tucao/utils/site_url.dart';

/// 站点正文默认字号, 单位是网页像素.
///
/// 站点字号写的是网页像素, 界面按它与默认字号的比例缩放, 见渲染组件.
const richBaseFontSize = 14.0;

/// 把站点富文本解析成 [RichBlock] 列表, 按页面顺序排列.
///
/// 只认站点编辑器实际会写的东西: 段落类块级标签, br, img, a, 加粗斜体等
/// 行内标签, `<font>` 的颜色与字号, 以及 style 里的 color, font-size,
/// font-weight, font-style, text-decoration, text-align. 其余标签只取文字.
List<RichBlock> parseRichHtml(Node root) => _RichHtmlParser().parse(root);

/// 会断开段落的块级标签, 其余标签当作行内元素.
///
/// 表格的 `table` 与格子的 `td` 不在此列, 它们由 [_RichHtmlParser] 单独
/// 收集成 [RichTable], 见 [_RichHtmlParser._parseTable].
const _blockTags = {
  'p', 'div', 'li', 'ul', 'ol', 'dl', 'dd', 'dt', 'blockquote', 'pre',
  'section', 'article', 'figure', 'figcaption', 'center',
  'h1', 'h2', 'h3', 'h4', 'h5', 'h6',
};

/// 表格里承载行的标签, 表格可能是 `table > tr` 也可能是 `table > tbody > tr`.
const _tableSections = {'thead', 'tbody', 'tfoot'};

/// 不属于正文的标签, 连同子节点一起跳过.
const _ignoredTags = {
  'script', 'style', 'iframe', 'noscript', 'input', 'button', 'select',
  'textarea', 'object', 'embed', 'video', 'audio', 'svg', 'head', 'title',
  'meta', 'link',
};

/// 标题标签的字号, 单位是网页像素, 与浏览器默认比例一致.
const _headingSizes = {
  'h1': 24.0, 'h2': 20.0, 'h3': 18.0, 'h4': 16.0, 'h5': 14.0, 'h6': 13.0,
};

/// `<font size="1..7">` 对应的字号, 3 是正文默认字号.
const _fontTagSizes = {
  '1': 9.0, '2': 11.0, '3': 14.0, '4': 16.0, '5': 21.0, '6': 28.0, '7': 42.0,
};

/// 正文里出现过的颜色名, 其余颜色站点编辑器都写成十六进制.
const _namedColors = {
  'black': 0xFF000000,
  'white': 0xFFFFFFFF,
  'red': 0xFFFF0000,
  'green': 0xFF008000,
  'blue': 0xFF0000FF,
  'gray': 0xFF808080,
  'grey': 0xFF808080,
  'silver': 0xFFC0C0C0,
  'maroon': 0xFF800000,
  'purple': 0xFF800080,
  'orange': 0xFFFFA500,
  'yellow': 0xFFFFFF00,
  'navy': 0xFF000080,
  'teal': 0xFF008080,
  'pink': 0xFFFFC0CB,
};

class _RichHtmlParser {
  final _out = <RichBlock>[];

  /// 当前段落里还没落成段落的文字.
  final _pending = <RichSpan>[];

  /// 当前段落的对齐方式, 由外层块级元素决定.
  TextAlign? _align;

  /// 正在收集的一行图片, 遇到文字, 换行或段落结束时落成 [RichImageRow].
  final _row = <RichImage>[];

  /// 这一行图片所在段落的对齐方式.
  TextAlign? _rowAlign;

  List<RichBlock> parse(Node root) {
    _walkChildren(root, RichStyle.plain);
    _flush();
    // 正文开头与末尾的空行没有意义, 只保留夹在内容中间的.
    while (_out.isNotEmpty && _out.first is RichSpacer) {
      _out.removeAt(0);
    }
    while (_out.isNotEmpty && _out.last is RichSpacer) {
      _out.removeLast();
    }
    return List<RichBlock>.unmodifiable(_out);
  }

  void _walkChildren(Node node, RichStyle style) {
    for (final child in node.nodes) {
      if (child is Text) {
        _writeText(child.text, style);
      } else if (child is Element) {
        _walkElement(child, style);
      }
    }
  }

  void _walkElement(Element element, RichStyle inherited) {
    final tag = element.localName ?? '';
    if (_ignoredTags.contains(tag)) {
      return;
    }
    if (tag == 'br') {
      _writeLineBreak(inherited);
      return;
    }
    if (tag == 'img') {
      _addImage(element);
      return;
    }
    if (tag == 'hr') {
      _flush();
      _out.add(const RichRule());
      return;
    }
    if (tag == 'table') {
      final table = _parseTable(element);
      if (table != null) {
        _flush();
        _out.add(table);
      }
      return;
    }

    final css = _CssDeclarations.parse(element.attributes['style'] ?? '');
    final style = css.applyTo(_tagStyle(element, tag, inherited), inherited);

    // Cloudflare 把正文里的邮箱换成了 `[email protected]`, 真实地址按位
    // 异或后放在 data-cfemail 里, 浏览器靠脚本还原, 这里直接解出来.
    final cfEmail = element.attributes['data-cfemail'];
    if (cfEmail != null) {
      final email = _decodeCfEmail(cfEmail);
      if (email != null) {
        _writeRaw(email, style);
        return;
      }
    }

    if (!_blockTags.contains(tag)) {
      _walkChildren(element, style);
      return;
    }

    _flush();
    final outerAlign = _align;
    _align =
        css.align ??
        _parseAlign(element.attributes['align'] ?? '') ??
        (tag == 'center' ? TextAlign.center : outerAlign);
    final before = _out.length;
    if (tag == 'li') {
      _writeRaw('• ', style);
    }
    _walkChildren(element, style);
    _flush();
    _align = outerAlign;
    // 站点用 `<p>&nbsp;</p>` 撑出空行, 什么都没产出的段落记成空行.
    if (tag == 'p' && _out.length == before) {
      _out.add(const RichSpacer());
    }
  }

  /// 标签本身带的样式, style 属性在此之上再叠加.
  RichStyle _tagStyle(Element element, String tag, RichStyle style) {
    switch (tag) {
      case 'b' || 'strong':
        return style.merge(bold: true);
      case 'i' || 'em' || 'cite':
        return style.merge(italic: true);
      case 'u' || 'ins':
        return style.merge(underline: true);
      case 's' || 'strike' || 'del':
        return style.merge(lineThrough: true);
      case 'a':
        return style.merge(url: _linkUrl(element));
      case 'font':
        return style.merge(
          color: parseCssColor(element.attributes['color'] ?? ''),
          fontSize: _fontTagSizes[element.attributes['size']?.trim()],
        );
    }
    final headingSize = _headingSizes[tag];
    if (headingSize != null) {
      return style.merge(bold: true, fontSize: headingSize);
    }
    return style;
  }

  /// 写入一个文本节点, 空白按浏览器的规则折叠.
  ///
  /// 源码里的缩进与换行在浏览器里只是一个空格, 段首与换行后的空格不显示.
  /// `&nbsp;` 不折叠, 站点用它做段首缩进.
  void _writeText(String raw, RichStyle style) {
    var text = raw.replaceAll(RegExp(r'[ \t\r\n\f]+'), ' ');
    if (text.startsWith(' ') && _endsWithBreakOrSpace()) {
      text = text.substring(1);
    }
    _writeRaw(text, style);
  }

  void _writeLineBreak(RichStyle style) {
    // 换行前的空格在浏览器里不显示.
    if (_pending.isNotEmpty && _pending.last.text.endsWith(' ')) {
      final last = _pending.removeLast();
      final text = last.text.trimRight();
      if (text.isNotEmpty) {
        _pending.add(RichSpan(text, last.style));
      }
    }
    _writeRaw('\n', style);
  }

  void _writeRaw(String text, RichStyle style) {
    if (text.isEmpty) {
      return;
    }
    // 图片后面出现文字或换行, 这一行图片到此为止. 图片之间只有空白时,
    // 空白在浏览器里只是图片间的一点空隙, 直接丢掉.
    if (_row.isNotEmpty && (text.trim().isNotEmpty || text.contains('\n'))) {
      _pending.clear();
      _closeRow();
    }
    // 相邻同样式的文字合成一段, 减少渲染时的 span 数量.
    if (_pending.isNotEmpty && _pending.last.style == style) {
      final last = _pending.removeLast();
      _pending.add(RichSpan(last.text + text, style));
      return;
    }
    _pending.add(RichSpan(text, style));
  }

  bool _endsWithBreakOrSpace() {
    if (_pending.isEmpty) {
      return true;
    }
    final text = _pending.last.text;
    return text.endsWith(' ') || text.endsWith('\n');
  }

  /// 落下正在收集的一行图片.
  void _closeRow() {
    if (_row.isEmpty) {
      return;
    }
    _out.add(
      RichImageRow(List<RichImage>.unmodifiable(_row), align: _rowAlign),
    );
    _row.clear();
  }

  /// 把缓冲的图片与文字落成块, 只有空白的段落直接丢弃.
  ///
  /// 收集中的图片一定排在缓冲文字前面: 图片后面出现文字时这一行已经落下,
  /// 剩下的只会是图片之间的空白.
  void _flush() {
    _closeRow();
    if (_pending.isEmpty) {
      return;
    }
    final spans = _trimEdges(_pending);
    _pending.clear();
    if (spans.map((span) => span.text).join().trim().isEmpty) {
      return;
    }
    _out.add(
      RichParagraph(
        List<RichSpan>.unmodifiable([
          // 保留下来的 nbsp 已经起完缩进的作用, 换成普通空格, 复制时更干净.
          for (final span in spans)
            RichSpan(span.text.replaceAll('\u00a0', ' '), span.style),
        ]),
        align: _align,
      ),
    );
  }

  /// 去掉段落首尾的空格与换行, 段首的 nbsp 缩进保留.
  static List<RichSpan> _trimEdges(List<RichSpan> source) {
    final spans = [...source];
    while (spans.isNotEmpty) {
      final text = spans.first.text.replaceFirst(RegExp(r'^[ \n]+'), '');
      if (text.isNotEmpty) {
        spans[0] = RichSpan(text, spans.first.style);
        break;
      }
      spans.removeAt(0);
    }
    while (spans.isNotEmpty) {
      final text = spans.last.text.replaceFirst(RegExp('[ \n\u00a0]+\$'), '');
      if (text.isNotEmpty) {
        spans[spans.length - 1] = RichSpan(text, spans.last.style);
        break;
      }
      spans.removeLast();
    }
    return spans;
  }

  /// 把一张表格收成 [RichTable].
  ///
  /// 站点用表格排新番时间表与年度数据快照, 列宽写在格子的 `width` 上,
  /// 表头用 `<th>`, 格子里的内容可能是图片加标题. 行可能包在 `tbody` 里,
  /// 也可能直接挂在 `table` 下, 两种都认. 嵌套表格不再展开, 免得表格套表格.
  RichTable? _parseTable(Element table) {
    final rows = <RichTableRow>[];

    void collect(Element node) {
      for (final child in node.children) {
        final name = child.localName ?? '';
        if (name == 'tr') {
          final row = _parseRow(child);
          if (row != null) {
            rows.add(row);
          }
        } else if (_tableSections.contains(name)) {
          collect(child);
        }
      }
    }

    collect(table);
    return rows.isEmpty
        ? null
        : RichTable(List<RichTableRow>.unmodifiable(rows));
  }

  RichTableRow? _parseRow(Element tr) {
    final cells = <RichTableCell>[];
    for (final child in tr.children) {
      final name = child.localName ?? '';
      if (name == 'td' || name == 'th') {
        cells.add(_parseCell(child));
      }
    }
    return cells.isEmpty
        ? null
        : RichTableRow(List<RichTableCell>.unmodifiable(cells));
  }

  /// 一格的内容用独立的解析器收成块.
  ///
  /// 时间表的格子里是 "封面图 + 换行 + 标题", 数据快照的格子里是几行居中
  /// 的数字, 都按段落与图片处理. 格子本身的对齐与底色记在单元格上, 段落
  /// 自己写了对齐时以段落为准.
  RichTableCell _parseCell(Element cell) {
    final css = _CssDeclarations.parse(cell.attributes['style'] ?? '');
    return RichTableCell(
      blocks: _RichHtmlParser().parse(cell),
      widthFactor: _percentFactor(
        css.width ?? cell.attributes['width']?.trim() ?? '',
      ),
      background:
          css.background ?? parseCssColor(cell.attributes['bgcolor'] ?? ''),
      align: css.align ?? _parseAlign(cell.attributes['align'] ?? ''),
      header: cell.localName == 'th',
    );
  }

  /// 图片前后的文字分属两个段落, 中间没有文字的相邻图片排在同一行.
  ///
  /// 包在链接里的图片也按图片处理, 点开进入图片查看, 不跟随链接.
  void _addImage(Element image) {
    final src =
        image.attributes['src']?.trim() ??
        image.attributes['data-src']?.trim() ??
        '';
    if (src.isEmpty || src.startsWith('data:')) {
      return;
    }
    if (_row.isEmpty) {
      _flush();
      _rowAlign = _align;
    } else {
      // 能走到这里说明两张图片之间只有空白, 见 [_writeRaw].
      _pending.clear();
    }
    final css = _CssDeclarations.parse(image.attributes['style'] ?? '');
    final width = css.width ?? image.attributes['width']?.trim() ?? '';
    final height = css.height ?? image.attributes['height']?.trim() ?? '';
    _row.add(
      RichImage(
        _absoluteUrl(src),
        widthFactor: _percentFactor(width)?.clamp(0.05, 1.0),
        maxWidth: _pixelValue(width),
        maxHeight: _pixelValue(height),
      ),
    );
  }
}

/// 一个元素 style 属性里认得的声明.
class _CssDeclarations {
  const _CssDeclarations({
    this.color,
    this.background,
    this.fontSize,
    this.bold,
    this.italic,
    this.underline,
    this.lineThrough,
    this.align,
    this.width,
    this.height,
  });

  final Color? color;

  /// 底色, 站点用它给表格的表头铺灰底.
  final Color? background;

  /// 字号原文, 相对单位要等到知道父元素字号时才能换算.
  final String? fontSize;

  final bool? bold;
  final bool? italic;
  final bool? underline;
  final bool? lineThrough;
  final TextAlign? align;

  /// 宽度原文, 只给图片与表格格子用.
  final String? width;

  /// 高度原文, 只给图片用.
  final String? height;

  static _CssDeclarations parse(String raw) {
    if (raw.trim().isEmpty) {
      return const _CssDeclarations();
    }
    Color? color;
    Color? background;
    String? fontSize;
    bool? bold;
    bool? italic;
    bool? underline;
    bool? lineThrough;
    TextAlign? align;
    String? width;
    String? height;
    for (final declaration in raw.split(';')) {
      final colon = declaration.indexOf(':');
      if (colon <= 0) {
        continue;
      }
      final name = declaration.substring(0, colon).trim().toLowerCase();
      final value = declaration
          .substring(colon + 1)
          .replaceAll(RegExp(r'!important', caseSensitive: false), '')
          .trim()
          .toLowerCase();
      switch (name) {
        case 'color':
          color = parseCssColor(value);
        case 'background-color':
          background = parseCssColor(value);
        case 'background':
          // 站点的简写里只有颜色, 带图片或渐变的取不出颜色, 忽略即可.
          background = parseCssColor(value) ?? background;
        case 'font-size':
          fontSize = value;
        case 'font-weight':
          final number = int.tryParse(value);
          bold = number != null
              ? number >= 600
              : value == 'bold' || value == 'bolder'
              ? true
              : value == 'normal' || value == 'lighter'
              ? false
              : null;
        case 'font-style':
          italic = value == 'italic' || value == 'oblique'
              ? true
              : value == 'normal'
              ? false
              : null;
        case 'text-decoration' || 'text-decoration-line':
          if (value.contains('none')) {
            underline = false;
            lineThrough = false;
          } else {
            if (value.contains('underline')) {
              underline = true;
            }
            if (value.contains('line-through')) {
              lineThrough = true;
            }
          }
        case 'text-align':
          align = _parseAlign(value);
        case 'width':
          width = value;
        case 'height':
          height = value;
      }
    }
    return _CssDeclarations(
      color: color,
      background: background,
      fontSize: fontSize,
      bold: bold,
      italic: italic,
      underline: underline,
      lineThrough: lineThrough,
      align: align,
      width: width,
      height: height,
    );
  }

  RichStyle applyTo(RichStyle style, RichStyle inherited) {
    final size = fontSize;
    return style.merge(
      color: color,
      fontSize: size == null ? null : _parseFontSize(size, inherited.fontSize),
      bold: bold,
      italic: italic,
      underline: underline,
      lineThrough: lineThrough,
    );
  }
}

/// 解析站点写的百分比尺寸, 换算成 0 到 1 之间的比例.
double? _percentFactor(String raw) {
  final match = RegExp(r'^([\d.]+)\s*%$').firstMatch(raw.trim());
  final number = match == null ? null : double.tryParse(match.group(1)!);
  return number == null || number <= 0 ? null : number / 100;
}

/// 解析站点写的像素尺寸, 不带单位时按像素算.
double? _pixelValue(String raw) {
  final match = RegExp(r'^([\d.]+)\s*(?:px)?$').firstMatch(raw.trim());
  final number = match == null ? null : double.tryParse(match.group(1)!);
  return number == null || number <= 0 ? null : number;
}

/// 解析 CSS 颜色, 支持十六进制, rgb(), rgba() 与常见颜色名.
Color? parseCssColor(String raw) {
  final value = raw.trim().toLowerCase();
  if (value.isEmpty) {
    return null;
  }
  final hex = RegExp(r'^#([0-9a-f]{3}|[0-9a-f]{6})$').firstMatch(value);
  if (hex != null) {
    var digits = hex.group(1)!;
    if (digits.length == 3) {
      digits = digits.split('').map((digit) => '$digit$digit').join();
    }
    return Color(0xFF000000 | int.parse(digits, radix: 16));
  }
  final rgb = RegExp(
    r'^rgba?\(\s*(\d{1,3})\s*,\s*(\d{1,3})\s*,\s*(\d{1,3})\s*(?:,\s*([\d.]+)\s*)?\)$',
  ).firstMatch(value);
  if (rgb != null) {
    int channel(int group) => int.parse(rgb.group(group)!).clamp(0, 255);
    final alpha = double.tryParse(rgb.group(4) ?? '') ?? 1.0;
    return Color.fromARGB(
      (alpha.clamp(0.0, 1.0) * 255).round(),
      channel(1),
      channel(2),
      channel(3),
    );
  }
  final named = _namedColors[value];
  return named == null ? null : Color(named);
}

/// 解析 CSS 字号, 结果单位是网页像素.
///
/// em 与百分比相对父元素字号, 父元素没写时按正文默认字号算.
double? _parseFontSize(String raw, double? inherited) {
  final value = raw.trim().toLowerCase();
  final match = RegExp(r'^([\d.]+)\s*(px|pt|em|rem|%)?$').firstMatch(value);
  if (match == null) {
    return const {
      'xx-small': 9.0,
      'x-small': 10.0,
      'small': 12.0,
      'medium': 14.0,
      'large': 16.0,
      'x-large': 21.0,
      'xx-large': 28.0,
    }[value];
  }
  final number = double.tryParse(match.group(1)!);
  if (number == null || number <= 0) {
    return null;
  }
  final parent = inherited ?? richBaseFontSize;
  return switch (match.group(2)) {
    'pt' => number * 4 / 3,
    'em' => number * parent,
    'rem' => number * richBaseFontSize,
    '%' => number / 100 * parent,
    _ => number,
  };
}

TextAlign? _parseAlign(String raw) => switch (raw.trim().toLowerCase()) {
  'left' || 'start' => TextAlign.left,
  'center' || 'middle' => TextAlign.center,
  'right' || 'end' => TextAlign.right,
  'justify' => TextAlign.justify,
  _ => null,
};

/// 链接地址, 只保留能安全打开的 http(s) 与邮箱链接.
String? _linkUrl(Element link) {
  final href = link.attributes['href']?.trim() ?? '';
  // Cloudflare 混淆过的邮箱链接, 地址写在 data-cfemail 或 href 的锚点里.
  if (href.contains('/cdn-cgi/l/email-protection')) {
    final hash = href.indexOf('#');
    final encoded =
        link.attributes['data-cfemail'] ??
        (hash < 0 ? '' : href.substring(hash + 1));
    final email = _decodeCfEmail(encoded);
    return email == null ? null : 'mailto:$email';
  }
  if (href.isEmpty || href.startsWith('#')) {
    return null;
  }
  final url = _absoluteUrl(href);
  final scheme = Uri.tryParse(url)?.scheme.toLowerCase();
  return scheme == 'http' || scheme == 'https' || scheme == 'mailto'
      ? url
      : null;
}

/// 补全站内相对地址; 已经带协议的原样返回, 协议相对的地址按 https 处理.
String _absoluteUrl(String raw) {
  if (RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*:').hasMatch(raw)) {
    return raw;
  }
  if (raw.startsWith('//')) {
    return 'https:$raw';
  }
  return absoluteSiteUrl(raw);
}

/// 还原 Cloudflare 混淆的邮箱: 第一个字节是密钥, 其余字节与它异或.
String? _decodeCfEmail(String encoded) {
  final hex = encoded.trim();
  if (hex.length < 4 || hex.length.isOdd) {
    return null;
  }
  final key = int.tryParse(hex.substring(0, 2), radix: 16);
  if (key == null) {
    return null;
  }
  final bytes = <int>[];
  for (var index = 2; index < hex.length; index += 2) {
    final byte = int.tryParse(hex.substring(index, index + 2), radix: 16);
    if (byte == null) {
      return null;
    }
    bytes.add(byte ^ key);
  }
  try {
    return utf8.decode(bytes);
  } on FormatException {
    return null;
  }
}
