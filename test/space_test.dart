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
