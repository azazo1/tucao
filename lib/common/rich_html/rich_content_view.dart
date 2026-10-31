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
/// 宽度铺开, 点开进入全屏查看. 组件本身不滚动, 由外层列表负责.
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
            final RichImage image => Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: _RichImageView(
                image: image,
                title: imageTitle,
                prefix: imagePrefix,
              ),
            ),
            RichSpacer() => const SizedBox(height: 12),
          },
      ],
    );
  }
}

/// 一个段落, 链接单独上色并可点击.
class _RichParagraphText extends StatefulWidget {
  const _RichParagraphText({required this.paragraph});

  final RichParagraph paragraph;

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
      textAlign: widget.paragraph.align ?? TextAlign.start,
    );
  }

  TextStyle _spanStyle(RichStyle style, ColorScheme scheme, double baseSize) {
    final isLink = style.url != null;
    final color = _readableColor(style.color, scheme.surface);
    final linkColor = color ?? scheme.primary;
    return TextStyle(
      fontWeight: style.bold ? FontWeight.bold : null,
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
    final a = color.computeLuminance();
    final b = background.computeLuminance();
    // 阈值取 2: 站点常用的灰色小标题 #999999 在白底上约 2.85, 要保留;
    // 深色模式下 #333333 这类深色字约 1.5, 交还给主题.
    final contrast = (math.max(a, b) + 0.05) / (math.min(a, b) + 0.05);
    return contrast < 2 ? null : color;
  }
}

/// 正文里的图片.
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
    final image = widget.image;
    return Align(
      alignment: switch (image.align) {
        TextAlign.center => Alignment.center,
        TextAlign.right || TextAlign.end => Alignment.centerRight,
        _ => Alignment.centerLeft,
      },
      child: _sized(
        image,
        _allowed ? _buildImage(context, scheme) : _buildBlocked(scheme),
      ),
    );
  }

  /// 按站点写的宽度约束图片, 没写时铺满内容宽度.
  Widget _sized(RichImage image, Widget child) {
    final factor = image.widthFactor;
    if (factor != null) {
      return FractionallySizedBox(widthFactor: factor, child: child);
    }
    final maxWidth = image.maxWidth;
    if (maxWidth != null) {
      return ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      );
    }
    return child;
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
        child: Text(
          '站外图片, 点击加载',
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
      ),
    );
  }

  Widget _buildImage(BuildContext context, ColorScheme scheme) {
    final cacheWidth =
        (MediaQuery.sizeOf(context).width *
                MediaQuery.devicePixelRatioOf(context))
            .round();
    return GestureDetector(
      onTap: _open,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: CachedNetworkImage(
          imageUrl: widget.image.url,
          width: double.infinity,
          fit: BoxFit.fitWidth,
          memCacheWidth: cacheWidth,
          placeholder: (context, url) =>
              Container(height: 120, color: scheme.surfaceContainerHighest),
          errorWidget: (context, url, error) => Container(
            height: 120,
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
