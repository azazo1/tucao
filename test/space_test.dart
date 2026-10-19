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

    test('头像随资料刷新更新缓存键, 横幅与投稿封面不受影响', () {
      final raw = File('test/fixtures/space.html').readAsStringSync();
      final first = SpaceHttp.parseSpaceHtml(
        raw,
        9599,
        1,
        avatarRevision: 100,
      );
      final refreshed = SpaceHttp.parseSpaceHtml(
        raw,
        9599,
        1,
        avatarRevision: 101,
      );
      final originalUrl = Uri.parse(page.info.avatar);
      final firstUrl = Uri.parse(first.info.avatar);
      final refreshedUrl = Uri.parse(refreshed.info.avatar);

      expect(firstUrl.path, originalUrl.path);
      expect(firstUrl.origin, originalUrl.origin);
      expect(firstUrl.queryParameters['_avatar_v'], '100');
      expect(refreshedUrl.queryParameters['_avatar_v'], '101');
      expect(refreshed.info.avatar, isNot(first.info.avatar));
      expect(refreshed.info.banner, page.info.banner);
      expect(
        refreshed.list.map((item) => item.cover),
        page.list.map((item) => item.cover),
      );
    });

    test('头像相对路径补全并保留已有参数, 旧版本参数被替换', () {
      final parsed = SpaceHttp.parseSpaceHtml(
        '<div class="sheader"><img class="avatar" '
        'src="/avatar/180x180.jpg?size=180&amp;tag=a&amp;tag=b'
        '&amp;_avatar_v=99#preview"></div>',
        1,
        1,
        avatarRevision: 100,
      );
      final avatar = Uri.parse(parsed.info.avatar);
      expect(avatar.isAbsolute, isTrue);
      expect(avatar.path, '/avatar/180x180.jpg');
      expect(avatar.queryParametersAll, {
        'size': ['180'],
        'tag': ['a', 'b'],
        '_avatar_v': ['100'],
      });
      expect(avatar.fragment, 'preview');
    });

    test('缺少头像时不生成只有版本参数的图片地址', () {
      final parsed = SpaceHttp.parseSpaceHtml(
        '<div class="sheader"></div>',
        1,
        1,
        avatarRevision: 100,
      );
      expect(parsed.info.avatar, isEmpty);
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
