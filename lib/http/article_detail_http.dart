import 'package:dio/dio.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:tucao/common/constants.dart';
import 'package:tucao/common/rich_html/rich_content.dart';
import 'package:tucao/common/rich_html/rich_html_parser.dart';
import 'package:tucao/utils/http_util.dart';

/// 档案详情.
class ArticleDetail {
  const ArticleDetail({
    required this.hid,
    required this.title,
    required this.cover,
    required this.tags,
    required this.blocks,
    this.category = '',
    this.publishedAt = '',
    this.commentTypeId = 0,
  });

  final String hid;
  final String title;

  /// 头图, 取自 og:image.
  final String cover;

  /// 分类, 取自详情页顶部的面包屑, 如 情报, 公告.
  final String category;

  /// 发布时间原文, 形如 `2026-10-11 20:21:12`.
  final String publishedAt;

  /// 评论楼层里的分区 id, 取自页面里的 `commentid=content_41-...`.
  ///
  /// 档案统一用 41, 取不到时为 0, 此时不显示评论区.
  final int commentTypeId;

  /// 正文里以 # 开头的标签.
  final List<String> tags;

  /// 正文分块, 按页面顺序保留段落, 图片与空行, 段落内带样式与链接.
  final List<RichBlock> blocks;
}

/// 档案详情数据源.
abstract final class ArticleDetailHttp {
  static Future<ArticleDetail> fetch({
    required String hid,
    CancelToken? cancelToken,
  }) async {
    final response = await HttpUtil.dio.get(
      '${Constants.baseUrl}play/d$hid/',
      options: Options(headers: {'user-agent': Constants.desktopUserAgent}),
      cancelToken: cancelToken,
    );
    return parseDetailHtml(response.data.toString(), hid);
  }

  /// 解析详情页面.
  ///
  /// 档案详情沿用播放页模板, 正文固定在 `.show_content` 里,
  /// 里面混排文字与图片, 这里按出现顺序还原成段落列表.
  static ArticleDetail parseDetailHtml(String raw, String hid) {
    final document = html_parser.parse(raw);
    final title =
        document.querySelector('h1.show_title')?.text.trim() ??
        document.querySelector('h1')?.text.trim() ??
        '';
    final cover =
        document
            .querySelector('meta[property="og:image"]')
            ?.attributes['content'] ??
        '';
    final header = _parseHeader(
      document.querySelector('.show_top .l .t')?.text.trim() ?? '',
    );
    final commentTypeId = _parseCommentTypeId(raw);

    final content = _contentContainer(document);
    final blocks = <RichBlock>[];
    final tags = <String>[];
    if (content != null) {
      // 站点在正文末尾放了一个清除浮动用的空块, 不属于正文.
      for (final clear in content.querySelectorAll('div.clear')) {
        clear.remove();
      }
      for (final block in parseRichHtml(content)) {
        // 正文里形如 `#忍空` 的段落是标签, 单独收集. 带链接的段落仍算正文.
        if (block is RichParagraph &&
            block.spans.every((span) => span.style.url == null)) {
          final text = block.text.trim();
          if (RegExp(r'^(#[^\s#]+)+$').hasMatch(text)) {
            tags.addAll(
              text.split('#').map((e) => e.trim()).where((e) => e.isNotEmpty),
            );
            continue;
          }
        }
        blocks.add(block);
      }
      // 标签行拿走后, 末尾可能剩下空行.
      while (blocks.isNotEmpty && blocks.last is RichSpacer) {
        blocks.removeLast();
      }
    }

    return ArticleDetail(
      hid: hid,
      title: title,
      cover: cover,
      category: header.category,
      publishedAt: header.publishedAt,
      commentTypeId: commentTypeId,
      tags: tags,
      blocks: blocks,
    );
  }

  /// 正文容器.
  ///
  /// 档案页固定用 `.show_content`, 老页面没有这个类时,
  /// 取嵌套不深且文字最多的 div.
  static Element? _contentContainer(Document document) {
    final explicit = document.querySelector('.show_content');
    if (explicit != null) {
      return explicit;
    }
    Element? best;
    var bestLength = 0;
    for (final node in document.querySelectorAll('div')) {
      if (node.querySelectorAll('div').length > 6) {
        continue;
      }
      final length = node.text.trim().length;
      if (length > bestLength) {
        best = node;
        bestLength = length;
      }
    }
    return best ?? document.body;
  }

  /// 从评论 iframe 或脚本里的 `commentid=content_41-...` 取分区 id.
  static int _parseCommentTypeId(String raw) {
    final match = RegExp(r'commentid=content_(\d+)-').firstMatch(raw);
    if (match == null) {
      return 0;
    }
    return int.tryParse(match.group(1)!) ?? 0;
  }

  /// 面包屑形如 `档案 / 情报 / 2026-10-11 20:21:12`.
  static ({String category, String publishedAt}) _parseHeader(String text) {
    final parts = text
        .split('/')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (parts.length < 2) {
      return (category: '', publishedAt: '');
    }
    final hasDate = RegExp(r'\d{4}-\d{2}-\d{2}').hasMatch(parts.last);
    return (
      category: parts[parts.length - (hasDate ? 2 : 1)],
      publishedAt: hasDate ? parts.last : '',
    );
  }
}
