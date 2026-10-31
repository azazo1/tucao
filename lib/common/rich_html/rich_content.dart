import 'dart:ui' show Color, TextAlign;

/// 站点富文本解析后的结构.
///
/// 档案正文与系统公告都由站点编辑器生成, 用到的标签与样式不多, 这里只保留
/// 界面能还原的那部分: 段落, 图片, 空行, 以及段落内文字的加粗, 斜体, 下划线,
/// 删除线, 颜色, 字号与链接.
sealed class RichBlock {
  const RichBlock();
}

/// 一个段落, 段落内的文字按页面顺序排列, 换行已经写进文字里.
class RichParagraph extends RichBlock {
  const RichParagraph(this.spans, {this.align});

  final List<RichSpan> spans;

  /// 段落对齐, 站点没写时为 null, 按界面默认靠左.
  final TextAlign? align;

  String get text => spans.map((span) => span.text).join();
}

/// 独立成块的图片.
class RichImage extends RichBlock {
  const RichImage(this.url, {this.widthFactor, this.maxWidth, this.align});

  /// 已经补成绝对地址.
  final String url;

  /// 站点按百分比写的宽度, 换算成 0 到 1 之间的比例.
  final double? widthFactor;

  /// 站点按像素写的宽度, 界面里作为上限, 不超过内容宽度.
  final double? maxWidth;

  /// 图片所在段落的对齐方式.
  final TextAlign? align;
}

/// 站点用 `<p>&nbsp;</p>` 撑出来的空行.
class RichSpacer extends RichBlock {
  const RichSpacer();
}

/// 段落里同一样式的一段文字.
class RichSpan {
  const RichSpan(this.text, [this.style = RichStyle.plain]);

  final String text;

  final RichStyle style;
}

/// 一段文字的样式.
///
/// 只记录站点写明的部分, 没写的交给界面主题. [fontSize] 保留站点原始的
/// 像素值, 换算成界面字号由渲染组件决定.
class RichStyle {
  const RichStyle({
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.lineThrough = false,
    this.color,
    this.fontSize,
    this.url,
  });

  static const plain = RichStyle();

  final bool bold;
  final bool italic;
  final bool underline;
  final bool lineThrough;

  /// 站点指定的文字颜色, 为 null 时用主题颜色.
  final Color? color;

  /// 站点指定的字号, 单位是网页像素.
  final double? fontSize;

  /// 链接地址, 已补成绝对地址; 非空时这段文字是链接.
  final String? url;

  /// 在当前样式上叠加子元素的样式, 参数为 null 的部分沿用当前值.
  RichStyle merge({
    bool? bold,
    bool? italic,
    bool? underline,
    bool? lineThrough,
    Color? color,
    double? fontSize,
    String? url,
  }) {
    return RichStyle(
      bold: bold ?? this.bold,
      italic: italic ?? this.italic,
      underline: underline ?? this.underline,
      lineThrough: lineThrough ?? this.lineThrough,
      color: color ?? this.color,
      fontSize: fontSize ?? this.fontSize,
      url: url ?? this.url,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is RichStyle &&
      other.bold == bold &&
      other.italic == italic &&
      other.underline == underline &&
      other.lineThrough == lineThrough &&
      other.color == color &&
      other.fontSize == fontSize &&
      other.url == url;

  @override
  int get hashCode =>
      Object.hash(bold, italic, underline, lineThrough, color, fontSize, url);
}

/// 正文的纯文本, 用于选择菜单里的复制全文.
///
/// 图片与空行不进入剪贴板, 段落之间用换行分隔.
String richPlainText(Iterable<RichBlock> blocks) {
  final paragraphs = <String>[];
  for (final block in blocks) {
    if (block is! RichParagraph) {
      continue;
    }
    final text = block.text.trim();
    if (text.isNotEmpty) {
      paragraphs.add(text);
    }
  }
  return paragraphs.join('\n');
}
