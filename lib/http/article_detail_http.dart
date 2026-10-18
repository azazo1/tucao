import 'package:dio/dio.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:tucao/common/constants.dart';
import 'package:tucao/utils/http_util.dart';

/// 档案详情.
class ArticleDetail {
  const ArticleDetail({
    required this.hid,
    required this.title,
    required this.cover,
    required this.tags,
    required this.paragraphs,
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

  /// 正文段落, 已按原顺序保留图片与文本.
  final List<ArticleBlock> paragraphs;
}

/// 正文中的一段, 可能是文字也可能是图片.
class ArticleBlock {
  const ArticleBlock.text(this.text) : image = null;

  const ArticleBlock.image(this.image) : text = null;

  final String? text;
  final String? image;
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
    final blocks = <ArticleBlock>[];
    final tags = <String>[];
    if (content != null) {
      for (final node in content.nodes) {
        if (node is Text) {
          // 直接写在容器里的文字也要保留.
          final text = node.text.trim();
          if (text.isNotEmpty) {
            blocks.add(ArticleBlock.text(text));
          }
          continue;
        }
        if (node is! Element) {
          continue;
        }
        final tag = node.localName;
        if (tag == 'img') {
          _addImage(blocks, node.attributes['src'] ?? '');
          continue;
        }
        // 正文里形如 `#忍空` 的段落是标签, 单独收集.
        final text = node.text.trim();
        if (text.isNotEmpty) {
          if (RegExp(r'^(#[^\s#]+)+$').hasMatch(text)) {
            tags.addAll(
              text
                  .split(RegExp(r'\s+'))
                  .map((e) => e.replaceFirst('#', ''))
                  .where((e) => e.isNotEmpty),
            );
          } else {
            blocks.add(ArticleBlock.text(text));
          }
        }
        // 图片可能单独成段, 文字为空时也要保留.
        for (final image in node.querySelectorAll('img')) {
          _addImage(blocks, image.attributes['src'] ?? '');
        }
      }
      // 没有块级子节点时退化为整段文字.
      if (blocks.isEmpty) {
        final text = content.text.trim();
        if (text.isNotEmpty) {
          blocks.add(ArticleBlock.text(text));
        }
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
      paragraphs: blocks,
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

  static void _addImage(List<ArticleBlock> blocks, String src) {
    if (src.isEmpty) {
      return;
    }
    blocks.add(ArticleBlock.image(_absolute(src)));
  }

  static String _absolute(String url) {
    if (url.startsWith('http')) {
      return url;
    }
    return '${Constants.baseUrl}${url.replaceFirst(RegExp(r'^/'), '')}';
  }
}
