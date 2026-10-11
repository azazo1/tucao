import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tucao/http/space_http.dart';

void main() {
  group('用户空间解析', () {
    late SpacePage page;

    setUpAll(() {
      final raw = File('test/fixtures/space.html').readAsStringSync();
      page = SpaceHttp.parseSpaceHtml(raw, 9599, 1);
    });

    test('解析出用户信息', () {
      expect(page.info.userId, 9599);
      expect(page.info.userName, isNotEmpty);
      expect(page.info.avatar, startsWith('http'));
      expect(page.info.banner, startsWith('http'));
      expect(page.info.total, greaterThan(0));
    });

    test('解析出投稿列表且字段完整', () {
      expect(page.list, isNotEmpty);
      for (final item in page.list) {
        expect(item.hid, isNotEmpty);
        expect(item.title, isNotEmpty);
        expect(item.cover, isNotEmpty);
      }
      // 站点把真实封面写在 style 的 background-image 里,
      // 大多数条目应当解析到站点域名下的图片.
      final withCover = page.list.where(
        (e) => e.cover.contains('tucao.my'),
      );
      expect(withCover.length, greaterThan(page.list.length ~/ 2));
    });

    test('投稿 hid 不重复', () {
      final ids = page.list.map((e) => e.hid).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('取满一页时还有下一页', () {
      // 站点每页 50 条, 取满即认为还有下一页.
      expect(page.list.length, SpaceHttp.pageSize);
      expect(page.hasMore, isTrue);
    });

    test('未取满一页时视为最后一页', () {
      // 只保留前 3 条投稿, 应当判定为到底.
      final raw = File('test/fixtures/space.html').readAsStringSync();
      final listStart = raw.indexOf('<div class="list">');
      final items = RegExp(
        r'<div class="item">.*?</div></div>',
        dotAll: true,
      ).allMatches(raw.substring(listStart)).take(3).map((m) => m.group(0));
      final short = SpaceHttp.parseSpaceHtml(
        '<html><body><div class="list">${items.join()}</div></body></html>',
        9599,
        999,
      );
      expect(short.list, hasLength(3));
      expect(short.hasMore, isFalse);
    });

    test('空页面返回空列表而不是抛异常', () {
      final empty = SpaceHttp.parseSpaceHtml(
        '<html><body></body></html>',
        1,
        1,
      );
      expect(empty.list, isEmpty);
      expect(empty.info.userName, isEmpty);
    });
  });
}
