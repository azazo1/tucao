import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tucao/common/rich_html/rich_content.dart';
import 'package:tucao/common/rich_html/rich_html_parser.dart';
import 'package:tucao/common/rich_html/rich_link.dart';
import 'package:tucao/pages/mine/image_viewer_page.dart';
import 'package:tucao/utils/site_url.dart';

/// 按块渲染站点富文本.
///
/// 段落用 [Text.rich] 还原加粗, 颜色, 字号与链接, 图片按内容宽度或站点给的
/// 宽度铺开, 点开进入全屏查看, 表格按站点的列宽比例排开, 放不下时整表横向
/// 滚动. 组件本身不滚动, 由外层列表负责.
class RichContentView extends StatelessWidget {
  const RichContentView({
    super.key,
    required this.blocks,
    this.imageTitle,
    this.imagePrefix,
  });

  final List<RichBlock> blocks;

  /// 图片查看页的标题.
  final String? imageTitle;

  /// 保存图片时的文件名前缀.
  final String? imagePrefix;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final block in blocks)
          switch (block) {
            final RichParagraph paragraph => Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: _RichParagraphText(paragraph: paragraph),
            ),
            final RichImageRow row => Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: _RichImageRowView(
                row: row,
                title: imageTitle,
                prefix: imagePrefix,
              ),
            ),
            final RichTable table => Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: _RichTableView(
                table: table,
                title: imageTitle,
                prefix: imagePrefix,
              ),
            ),
            RichSpacer() => const SizedBox(height: 12),
            RichRule() => const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Divider(height: 1),
            ),
          },
      ],
    );
  }
}

/// 一个段落, 链接单独上色并可点击.
class _RichParagraphText extends StatefulWidget {
  const _RichParagraphText({
    required this.paragraph,
    this.fallbackAlign,
    this.forceBold = false,
    this.background,
  });

  final RichParagraph paragraph;

  /// 段落自己没写对齐时的兜底, 表格格子用它带上格子的对齐.
  final TextAlign? fallbackAlign;

  /// 整段强制加粗, 表格里的 `<th>` 表头用.
  final bool forceBold;

  /// 这段文字实际的底色.
  ///
  /// 判断站点颜色还看不看得清时以它为准, 表格格子会传进去; 段落直接铺在
  /// 页面背景上时为 null, 用主题的表面色.
  final Color? background;

  @override
  State<_RichParagraphText> createState() => _RichParagraphTextState();
}

class _RichParagraphTextState extends State<_RichParagraphText> {
  /// 与段落里的文字一一对应的链接手势, 只有链接位置非空.
  ///
  /// 手势识别器要自己回收, 因此跟随段落一起在这里维护, 不在 build 里新建.
  final _recognizers = <TapGestureRecognizer?>[];

  @override
  void initState() {
    super.initState();
    _buildRecognizers();
  }

  @override
  void didUpdateWidget(covariant _RichParagraphText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.paragraph, widget.paragraph)) {
      _releaseRecognizers();
      _buildRecognizers();
    }
  }

  @override
  void dispose() {
    _releaseRecognizers();
    super.dispose();
  }

  void _buildRecognizers() {
    for (final span in widget.paragraph.spans) {
      final url = span.style.url;
      _recognizers.add(
        url == null || url.isEmpty
            ? null
            : (TapGestureRecognizer()..onTap = () => openRichLink(url)),
      );
    }
  }

  void _releaseRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer?.dispose();
    }
    _recognizers.clear();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final base = theme.textTheme.bodyMedium?.copyWith(
      height: 1.7,
      color: scheme.onSurface,
    );
    final baseSize = base?.fontSize ?? 14;
    final spans = widget.paragraph.spans;
    return Text.rich(
      TextSpan(
        children: [
          for (var index = 0; index < spans.length; index++)
            TextSpan(
              text: spans[index].text,
              style: _spanStyle(spans[index].style, scheme, baseSize),
              recognizer: _recognizers[index],
            ),
        ],
      ),
      style: base,
      textAlign:
          widget.paragraph.align ?? widget.fallbackAlign ?? TextAlign.start,
    );
  }

  TextStyle _spanStyle(RichStyle style, ColorScheme scheme, double baseSize) {
    final isLink = style.url != null;
    final color = _readableColor(
      style.color,
      widget.background ?? scheme.surface,
    );
    final linkColor = color ?? scheme.primary;
    return TextStyle(
      fontWeight: widget.forceBold || style.bold ? FontWeight.bold : null,
      fontStyle: style.italic ? FontStyle.italic : null,
      fontSize: _displaySize(style.fontSize, baseSize),
      color: isLink ? linkColor : color,
      decoration: TextDecoration.combine([
        if (style.underline || isLink) TextDecoration.underline,
        if (style.lineThrough) TextDecoration.lineThrough,
      ]),
      decorationColor: isLink ? linkColor : color,
    );
  }

  /// 把站点字号换算成界面字号.
  ///
  /// 站点是桌面页面, 正文里常见 20px, 偶尔有 36px 的大字. 原样放大在手机上
  /// 一行放不下几个字, 这里按与站点正文字号的比例做平缓缩放, 并限制在
  /// 正文字号的 0.8 到 1.6 倍之间.
  static double? _displaySize(double? pixels, double baseSize) {
    if (pixels == null) {
      return null;
    }
    final ratio = math.pow(pixels / richBaseFontSize, 0.7).toDouble();
    return baseSize * ratio.clamp(0.8, 1.6);
  }

  /// 站点颜色是按白底挑的, 深色模式下与背景对比不够的颜色交还给主题.
  static Color? _readableColor(Color? color, Color background) {
    if (color == null || color.a == 0) {
      return null;
    }
    // 站点偶尔写半透明色, 先按它实际盖住的底色合成, 再判断看不看得清.
    final effective = color.a < 1 ? Color.alphaBlend(color, background) : color;
    final a = effective.computeLuminance();
    final b = background.computeLuminance();
    // 阈值取 2: 站点常用的灰色小标题 #999999 在白底上约 2.85, 要保留;
    // 深色模式下 #333333 这类深色字约 1.5, 交还给主题.
    final contrast = (math.max(a, b) + 0.05) / (math.min(a, b) + 0.05);
    return contrast < 2 ? null : effective;
  }
}

/// 一行图片, 按网页的行内排版排列.
///
/// 每张图的宽度按站点写的百分比或像素换算, 没写时占满整行; 一行放不下时
/// 换到下一行, 与浏览器一致. 五张 `width: 20%` 的截图因此并排成一行.
class _RichImageRowView extends StatelessWidget {
  const _RichImageRowView({required this.row, this.title, this.prefix});

  final RichImageRow row;
  final String? title;
  final String? prefix;

  /// 并排图片之间的空隙.
  static const _gap = 4.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final full = constraints.maxWidth;
        return Wrap(
          spacing: _gap,
          runSpacing: _gap,
          alignment: switch (row.align) {
            TextAlign.center => WrapAlignment.center,
            TextAlign.right || TextAlign.end => WrapAlignment.end,
            _ => WrapAlignment.start,
          },
          children: [
            for (final image in row.images)
              SizedBox(
                key: ValueKey(image.url),
                width: _imageWidth(image, full),
                child: _RichImageView(
                  image: image,
                  title: title,
                  prefix: prefix,
                ),
              ),
          ],
        );
      },
    );
  }

  /// 图片在界面里的宽度.
  ///
  /// 百分比宽度扣掉一点空隙, 合计正好 100% 的几张图仍能排进一行.
  static double _imageWidth(RichImage image, double full) {
    final factor = image.widthFactor;
    if (factor != null) {
      return factor >= 1 ? full : (full * factor - _gap).clamp(1.0, full);
    }
    final maxWidth = image.maxWidth;
    if (maxWidth != null) {
      return maxWidth.clamp(1.0, full);
    }
    return full;
  }
}

/// 一张表格.
///
/// 站点按桌面网页的宽度排版, 新番时间表是七列, 年度数据快照是八列, 手机上
/// 整表横向滚动, 保持列与列的对应关系. 列宽取格子上写的百分比, 没写的列按
/// 已写列的均值补, 全部没写时均分.
class _RichTableView extends StatelessWidget {
  const _RichTableView({required this.table, this.title, this.prefix});

  final RichTable table;
  final String? title;
  final String? prefix;

  /// 一列在手机上还看得清的下限, 低于它就把整表撑宽, 交给横向滚动.
  static const _minColumnWidth = 96.0;

  /// 格子内边距, 站点写的是 10px, 手机上收一点.
  static const _cellPadding = EdgeInsets.symmetric(horizontal: 6, vertical: 8);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = table.columnCount;
        if (columns == 0) {
          return const SizedBox.shrink();
        }
        final available = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : _minColumnWidth * columns;
        final widths = _columnWidths(table, available);
        final total = widths.fold(0.0, (sum, width) => sum + width);
        final content = Table(
          columnWidths: {
            for (var index = 0; index < widths.length; index++)
              index: FixedColumnWidth(widths[index]),
          },
          border: TableBorder.all(color: scheme.outlineVariant),
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: [
            for (final row in table.rows)
              TableRow(
                children: [
                  for (var index = 0; index < widths.length; index++)
                    _buildCell(
                      context,
                      index < row.cells.length ? row.cells[index] : null,
                    ),
                ],
              ),
          ],
        );
        if (total <= available + 0.5) {
          return content;
        }
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(width: total, child: content),
        );
      },
    );
  }

  /// 一格的内容按块渲染, 对齐以格子为准, 段落自己写了对齐时以段落为准.
  Widget _buildCell(BuildContext context, RichTableCell? cell) {
    if (cell == null) {
      return const SizedBox.shrink();
    }
    final scheme = Theme.of(context).colorScheme;
    final align = cell.align ?? (cell.header ? TextAlign.center : null);
    final background = _cellBackground(cell.background, scheme);
    return Container(
      color: background,
      padding: _cellPadding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: switch (align) {
          TextAlign.center => CrossAxisAlignment.center,
          TextAlign.right || TextAlign.end => CrossAxisAlignment.end,
          _ => CrossAxisAlignment.stretch,
        },
        children: [
          for (final block in cell.blocks)
            switch (block) {
              final RichParagraph paragraph => _RichParagraphText(
                paragraph: paragraph,
                fallbackAlign: align,
                forceBold: cell.header,
                background: background,
              ),
              final RichImageRow row => _RichImageRowView(
                row: row,
                title: title,
                prefix: prefix,
              ),
              final RichTable table => _RichTableView(
                table: table,
                title: title,
                prefix: prefix,
              ),
              RichSpacer() => const SizedBox(height: 6),
              RichRule() => const Divider(height: 1),
            },
        ],
      ),
    );
  }

  /// 把站点的格子底色搬到当前主题上.
  ///
  /// 站点是按白底挑的颜色, 表头常见 `rgb(238, 238, 238)` 这种浅灰. 底色必须
  /// 和跟着主题走的文字色处在同明暗的一端, 否则浅色字压浅色底会糊成一片.
  /// 因此深色模式把底色压进深色区间, 浅色模式把站点偶尔用的深色底提到浅色
  /// 区间, 两边都只动明度, 保住色相与饱和度. 明度越高的底压得越狠, 格子之间
  /// 原来的深浅关系仍然分得开.
  static Color? _cellBackground(Color? raw, ColorScheme scheme) {
    if (raw == null || raw.a == 0) {
      return null;
    }
    final hsl = HSLColor.fromColor(raw);
    if (scheme.brightness == Brightness.dark) {
      return hsl.withLightness(0.10 + hsl.lightness * 0.14).toColor();
    }
    if (hsl.lightness < 0.5) {
      return hsl.withLightness(0.84 + hsl.lightness * 0.10).toColor();
    }
    return raw;
  }

  /// 计算各列宽度.
  ///
  /// 先按站点写的百分比得到每列的占比, 没写宽度的列按已写列的均值补. 再检查
  /// 最窄的一列是否够宽: 不够就把整表按比例撑宽, 让每一列都达到下限, 超出的
  /// 部分由外层的横向滚动消化.
  static List<double> _columnWidths(RichTable table, double available) {
    final columns = table.columnCount;
    final weights = List<double?>.filled(columns, null);
    for (final row in table.rows) {
      final count = math.min(row.cells.length, columns);
      for (var index = 0; index < count; index++) {
        final factor = row.cells[index].widthFactor;
        if (factor == null) {
          continue;
        }
        final current = weights[index];
        weights[index] = current == null ? factor : math.max(current, factor);
      }
    }
    final written = weights.whereType<double>().toList();
    final fallback = written.isEmpty
        ? 1 / columns
        : written.reduce((a, b) => a + b) / written.length;
    final ratios = [for (final weight in weights) weight ?? fallback];
    final sum = ratios.reduce((a, b) => a + b);
    final narrowest = ratios.reduce(math.min) / sum;
    final total = math.max(available, _minColumnWidth / narrowest);
    return [for (final ratio in ratios) total * ratio / sum];
  }
}

/// 正文里的图片, 宽度由外层的图片行决定.
///
/// 站外图片不自动联网, 与评论里的图片同一套规则, 免得正文里塞的外部地址
/// 一打开页面就让本机发请求.
class _RichImageView extends StatefulWidget {
  const _RichImageView({required this.image, this.title, this.prefix});

  final RichImage image;
  final String? title;
  final String? prefix;

  @override
  State<_RichImageView> createState() => _RichImageViewState();
}

class _RichImageViewState extends State<_RichImageView> {
  late bool _allowed = isSiteImage(widget.image.url);

  void _open() {
    Get.to(
      () => ImageViewerPage(
        url: widget.image.url,
        title: widget.title,
        prefix: widget.prefix,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _allowed ? _buildImage(context, scheme) : _buildBlocked(scheme);
  }

  Widget _buildBlocked(ColorScheme scheme) {
    return InkWell(
      onTap: () => setState(() => _allowed = true),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 120,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.all(6),
        // 并排的小图只有几十像素宽, 文字限制行数, 不撑破占位框.
        child: Text(
          '站外图片, 点击加载',
          textAlign: TextAlign.center,
          maxLines: 4,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
      ),
    );
  }

  Widget _buildImage(BuildContext context, ColorScheme scheme) {
    final image = widget.image;
    final height = image.maxHeight;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    // 时间表的缩略图只有几十像素宽, 按实际显示尺寸解码, 不必按整屏宽缓存.
    final cacheWidth =
        ((image.maxWidth ?? MediaQuery.sizeOf(context).width) * dpr).round();
    return GestureDetector(
      onTap: _open,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: CachedNetworkImage(
          imageUrl: image.url,
          width: double.infinity,
          height: height,
          // 站点同时给了宽高时按原图比例摆在框里, 不拉伸; 否则铺满宽度.
          fit: height == null ? BoxFit.fitWidth : BoxFit.contain,
          memCacheWidth: cacheWidth,
          placeholder: (context, url) => Container(
            height: height ?? 120,
            color: scheme.surfaceContainerHighest,
          ),
          errorWidget: (context, url, error) => Container(
            height: height ?? 120,
            alignment: Alignment.center,
            color: scheme.surfaceContainerHighest,
            child: Icon(
              Icons.broken_image_outlined,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}
