import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:tucao/common/constants.dart';
import 'package:tucao/utils/http_util.dart';
import 'package:tucao/utils/logger.dart';

/// 档案页的一篇资讯.
class ArticleModel {
  const ArticleModel({
    required this.hid,
    required this.title,
    required this.category,
    required this.cover,
    required this.summary,
    required this.info,
  });

  /// 站内视频 id, 档案条目本身也是可播放的页面.
  final String hid;

  final String title;

  /// 分类, 如 情报, 公告, 年鉴.
  final String category;

  final String cover;

  /// 摘要正文.
  final String summary;

  /// 播放数与日期, 页面已拼好文案.
  final String info;
}

/// 档案页的分页结果.
class ArticlePage {
  const ArticlePage({
    required this.total,
    required this.page,
    required this.list,
    required this.hasMore,
  });

  /// 全站条目总数.
  final int total;

  final int page;
  final List<ArticleModel> list;

  /// 是否还有下一页, 由页面上的分页链接判断.
  final bool hasMore;
}

/// 档案页数据源.
///
/// 站点 `/data/` 是番组档案与资讯列表, 没有 json 接口, 只能抓页面.
/// 分页地址形如 `/data/index_2.html`.
abstract final class ArticleHttp {
  static const _pageSize = 20;

  /// 分类筛选项, 对应页面上的分类链接.
  ///
  /// 站点上的 `档案` 本身就是未筛选的列表, 由界面里的 `全部` 表示,
  /// 这里不再重复列出.
  static const categories = ['情报', '公告', '年鉴', 'anime', '动漫'];

  /// 拉取一页档案.
  ///
  /// [page] 从 1 开始, [keyword] 为空表示不按分类筛选.
  static Future<ArticlePage> fetch({
    int page = 1,
    String? keyword,
    CancelToken? cancelToken,
  }) async {
    final path = page <= 1 ? 'data/' : 'data/index_$page.html';
    final response = await HttpUtil.dio.get(
      '${Constants.baseUrl}$path',
      queryParameters: {
        if (keyword != null && keyword.isNotEmpty) 'keywords': keyword,
      },
      options: Options(headers: {'user-agent': Constants.desktopUserAgent}),
      cancelToken: cancelToken,
    );
    return parseArticleHtml(response.data.toString(), page);
  }

  /// 解析档案页面.
  ///
  /// 每条是 `div.item`, 左侧 `div.l` 是封面, 右侧 `div.r` 依次是分类 `div.c`,
  /// 标题 `div.t`, 播放信息 `div.tt` 与摘要 `div.d`.
  static ArticlePage parseArticleHtml(String raw, int page) {
    final document = html_parser.parse(raw);
    final list = <ArticleModel>[];
    final seen = <String>{};
    for (final item in document.querySelectorAll('.item')) {
      final link = item.querySelector('.t a');
      if (link == null) {
        continue;
      }
      final hid = _parseHid(link.attributes['href'] ?? '');
      if (hid == null || !seen.add(hid)) {
        continue;
      }
      list.add(
        ArticleModel(
          hid: hid,
          title: link.text.trim(),
          category: item.querySelector('.c')?.text.trim() ?? '',
          cover: item.querySelector('.l img')?.attributes['src'] ?? '',
          summary: item.querySelector('.d')?.text.trim() ?? '',
          info: item.querySelector('.tt')?.text.trim() ?? '',
        ),
      );
    }

    // 分页文案形如 "共5568条 / 第1页", 从里面取总数.
    final pagerText = document.querySelector('.title a')?.text.trim() ?? '';
    final total =
        int.tryParse(
          RegExp(r'共(\d+)条').firstMatch(pagerText)?.group(1) ?? '',
        ) ??
        0;

    final hasMore = document.querySelectorAll('a').any(
      (a) => (a.attributes['href'] ?? '').contains('index_${page + 1}.html'),
    );

    Log.i('档案第 $page 页解析完成, 共 ${list.length} 条');
    return ArticlePage(
      total: total,
      page: page,
      list: list,
      hasMore: hasMore || list.length >= _pageSize,
    );
  }

  static String? _parseHid(String href) {
    final match = RegExp(r'/play/[du]?(\d+)/').firstMatch(href);
    return match?.group(1);
  }
}
