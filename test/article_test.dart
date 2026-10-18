import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tucao/http/article_detail_http.dart';
import 'package:tucao/http/article_http.dart';

void main() {
  group('档案列表解析', () {
    late ArticlePage page;

    setUpAll(() {
      final raw = File('test/fixtures/article_list.html').readAsStringSync();
      page = ArticleHttp.parseArticleHtml(raw, 1);
    });

    test('解析出条目与总数', () {
      expect(page.list, isNotEmpty);
      expect(page.total, greaterThan(0));
      expect(page.page, 1);
    });

    test('条目字段完整', () {
      for (final item in page.list) {
        expect(item.hid, isNotEmpty);
        expect(item.title, isNotEmpty);
        expect(item.cover, startsWith('http'));
        expect(item.category, isNotEmpty);
      }
    });

    test('hid 不重复', () {
      final ids = page.list.map((e) => e.hid).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('空页面返回空列表', () {
      final empty = ArticleHttp.parseArticleHtml(
        '<html><body></body></html>',
        1,
      );
      expect(empty.list, isEmpty);
      expect(empty.total, 0);
    });
  });

  group('档案详情解析', () {
    late ArticleDetail detail;

    setUpAll(() {
      final raw = File('test/fixtures/article_detail.html').readAsStringSync();
      detail = ArticleDetailHttp.parseDetailHtml(raw, '7301');
    });

    test('解析出标题与头图', () {
      expect(detail.title, isNotEmpty);
      expect(detail.cover, startsWith('http'));
      expect(detail.hid, '7301');
    });

    test('解析出分类, 发布时间与评论分区', () {
      expect(detail.category, '情报');
      expect(detail.publishedAt, startsWith('2026-10-11'));
      // 档案评论楼层固定为 content_41-<hid>-1.
      expect(detail.commentTypeId, 41);
    });

    test('正文有内容', () {
      expect(detail.paragraphs, isNotEmpty);
      final texts = detail.paragraphs
          .where((e) => e.text != null)
          .map((e) => e.text!)
          .toList();
      expect(texts, isNotEmpty);
      // 正文段落应当有一定长度, 说明取到了正确的容器.
      expect(texts.any((e) => e.length > 50), isTrue);
      // 取的是 .show_content, 不应混入页头的面包屑.
      expect(texts.any((e) => e.contains('岸本')), isTrue);
      expect(texts.any((e) => e.contains('档案 / 情报')), isFalse);
    });

    test('图片地址补全为绝对地址', () {
      for (final block in detail.paragraphs) {
        if (block.image != null) {
          expect(block.image, startsWith('http'));
        }
      }
    });
  });
}
