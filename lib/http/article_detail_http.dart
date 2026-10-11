import 'package:dio/dio.dart';
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
  });

  final String hid;
  final String title;

  /// 头图, 取自 og:image.
  final String cover;

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
  /// 档案详情沿用播放页模板, 正文是页面里文字最多的那个容器,
  /// 里面混排文字与图片, 这里按出现顺序还原成段落列表.
  static ArticleDetail parseDetailHtml(String raw, String hid) {
    final document = html_parser.parse(raw);
    final title = document.querySelector('h1')?.text.trim() ?? '';
    final cover =
        document
            .querySelector('meta[property="og:image"]')
            ?.attributes['content'] ??
        '';

    // 正文容器: 取子 div 最少而文本最多的一个, 避开外层框架.
    var best = document.body;
    var bestLength = 0;
    if (best != null) {
      for (final node in document.querySelectorAll('div')) {
        final text = node.text.trim();
        final nested = node.querySelectorAll('div').length;
        if (nested < 12 && text.length > bestLength) {
          bestLength = text.length;
          best = node;
        }
      }
    }

    final blocks = <ArticleBlock>[];
    final tags = <String>[];
    if (best != null) {
      for (final node in best.children) {
        final tag = node.localName;
        if (tag == 'img') {
          final src = node.attributes['src'] ?? '';
          if (src.isNotEmpty) {
            blocks.add(ArticleBlock.image(_absolute(src)));
          }
          continue;
        }
        // 正文里形如 `#忍空` 的段落是标签, 单独收集.
        final text = node.text.trim();
        if (text.isEmpty) {
          continue;
        }
        if (RegExp(r'^(#[^\s#]+)+$').hasMatch(text)) {
          tags.addAll(
            text
                .split(RegExp(r'\s+'))
                .map((e) => e.replaceFirst('#', ''))
                .where((e) => e.isNotEmpty),
          );
          continue;
        }
        blocks.add(ArticleBlock.text(text));
        for (final image in node.querySelectorAll('img')) {
          final src = image.attributes['src'] ?? '';
          if (src.isNotEmpty) {
            blocks.add(ArticleBlock.image(_absolute(src)));
          }
        }
      }
    }

    return ArticleDetail(
      hid: hid,
      title: title,
      cover: cover,
      tags: tags,
      paragraphs: blocks,
    );
  }

  static String _absolute(String url) {
    if (url.startsWith('http')) {
      return url;
    }
    return '${Constants.baseUrl}${url.replaceFirst(RegExp(r'^/'), '')}';
  }
}
