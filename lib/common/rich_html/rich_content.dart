import 'dart:ui' show Color, TextAlign;

/// 站点富文本解析后的结构.
///
/// 档案正文与系统公告都由站点编辑器生成, 用到的标签与样式不多, 这里只保留
/// 界面能还原的那部分: 段落, 图片, 空行, 分隔线与表格, 以及段落内文字的
/// 加粗, 斜体, 下划线, 删除线, 颜色, 字号与链接.
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

/// 一行图片, 同一段落里中间没有文字的相邻图片归为一行.
///
/// 图片在网页里是行内元素, 站点常把几张 `width: 20%` 的截图并排贴在一个
/// 段落里, 浏览器会把它们排成一行, 放不下时才换行. 界面按同样的规则排列.
class RichImageRow extends RichBlock {
  const RichImageRow(this.images, {this.align});

  final List<RichImage> images;

  /// 图片所在段落的对齐方式.
  final TextAlign? align;
}

/// 正文里的一张图片.
class RichImage {
  const RichImage(this.url, {this.widthFactor, this.maxWidth, this.maxHeight});

  /// 已经补成绝对地址.
  final String url;

  /// 站点按百分比写的宽度, 换算成 0 到 1 之间的比例.
  final double? widthFactor;

  /// 站点按像素写的宽度, 界面里作为上限, 不超过内容宽度.
  final double? maxWidth;

  /// 站点写的高度, 单位是网页像素.
  ///
  /// 时间表里的封面写成 `width="70" height="45"` 这种固定尺寸, 宽度和高度
  /// 同时给出时按这个尺寸做上限, 图片不再按原图比例铺满整行.
  final double? maxHeight;
}

/// 站点用 `<p>&nbsp;</p>` 撑出来的空行.
class RichSpacer extends RichBlock {
  const RichSpacer();
}

/// 一条水平分隔线, 对应正文里的 `<hr>`.
///
/// 站点的更新日志常用它把两次改动隔开, 浏览器里是一条细线, 这里同样画线,
/// 不再退化成空行.
class RichRule extends RichBlock {
  const RichRule();
}

/// 一张表格.
///
/// 新番时间表与年度数据快照都是表格, 站点按网页的桌面宽度排版, 七到八列很
/// 常见, 手机上必须横向滚动才能看清列与列的对应关系, 因此表格整块交给
/// 渲染组件按列宽比例铺开, 见 [RichContentView].
class RichTable extends RichBlock {
  const RichTable(this.rows);

  /// 表格的行, 至少一行.
  final List<RichTableRow> rows;

  /// 列数, 取行里最宽的一行, 缺格的行在渲染时补空.
  int get columnCount => rows.fold(
    0,
    (max, row) => row.cells.length > max ? row.cells.length : max,
  );
}

/// 表格的一行.
class RichTableRow {
  const RichTableRow(this.cells);

  final List<RichTableCell> cells;
}

/// 表格里的一个格子.
///
/// 站点在格子里放的不只是文字: 新番时间表的每格是 "封面图 + 标题 + 链接",
/// 年度快照的每格是几行居中的数字, 因此格子里保留完整的块列表, 渲染时
/// 再按段落与图片排版.
class RichTableCell {
  const RichTableCell({
    required this.blocks,
    this.widthFactor,
    this.background,
    this.align,
    this.header = false,
  });

  final List<RichBlock> blocks;

  /// 站点在这格写的列宽比例, 取自 `width: 14%`, 没写时为 null.
  final double? widthFactor;

  /// 格子底色, 站点用它给表头铺灰底.
  final Color? background;

  /// 格子的默认对齐, 取自 `align` 属性或内联 `text-align`.
  ///
  /// 格子里的段落自己写了对齐时以段落为准.
  final TextAlign? align;

  /// 这一格来自 `<th>`, 渲染时加粗.
  final bool header;

  /// 格子里的纯文本, 用于复制全文.
  String get text => richPlainText(blocks);
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
/// 图片与空行不进入剪贴板, 段落之间用换行分隔. 表格里的文字按行拼起来,
/// 同一行的格子用制表符隔开, 复制出来的内容仍然对得上列.
String richPlainText(Iterable<RichBlock> blocks) {
  final paragraphs = <String>[];
  for (final block in blocks) {
    switch (block) {
      case RichParagraph():
        final text = block.text.trim();
        if (text.isNotEmpty) {
          paragraphs.add(text);
        }
      case RichTable():
        for (final row in block.rows) {
          final cells = [
            for (final cell in row.cells)
              cell.text.replaceAll('\n', ' ').trim(),
          ];
          final text = cells.join('\t').trim();
          if (text.isNotEmpty) {
            paragraphs.add(text);
          }
        }
      case RichImageRow() || RichSpacer() || RichRule():
        break;
    }
  }
  return paragraphs.join('\n');
}
