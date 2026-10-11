import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tucao/http/rank_http.dart';
import 'package:tucao/http/week_http.dart';

void main() {
  group('新番时间表解析', () {
    late List<WeekGroup> groups;

    setUpAll(() {
      final raw = File('test/fixtures/home_week.html').readAsStringSync();
      groups = WeekHttp.parseHomeHtml(raw);
    });

    test('分组数与站点标签一致', () {
      expect(groups.length, 9);
      expect(
        groups.map((e) => e.title).toList(),
        ['周日', '周一', '周二', '周三', '周四', '周五', '周六', '剧场', '天朝'],
      );
    });

    test('每个分组都解析出条目', () {
      for (final group in groups) {
        expect(group.list, isNotEmpty, reason: '${group.title} 分组为空');
      }
    });

    test('条目字段完整', () {
      final items = groups.expand((e) => e.list).toList();
      expect(items.length, greaterThan(50));
      for (final item in items) {
        expect(item.hid, isNotEmpty);
        expect(item.title, isNotEmpty);
        expect(item.cover, startsWith('http'));
      }
    });

    test('同一分组内 hid 不重复', () {
      for (final group in groups) {
        final ids = group.list.map((e) => e.hid).toList();
        expect(ids.toSet().length, ids.length, reason: '${group.title} 有重复条目');
      }
    });

    test('没有时间表时返回空列表而不是抛异常', () {
      expect(WeekHttp.parseHomeHtml('<html><body>空页面</body></html>'), isEmpty);
    });
  });

  group('排行榜解析', () {
    late List<RankGroup> groups;

    setUpAll(() {
      final raw = File('test/fixtures/rank.html').readAsStringSync();
      groups = RankHttp.parseRankHtml(raw);
    });

    test('解析出四个时间维度', () {
      expect(groups.map((e) => e.title).toList(), ['今天', '本周', '本月', '今年']);
      expect(groups.map((e) => e.period).toList(), [0, 1, 2, 3]);
    });

    test('每个维度都有条目且字段完整', () {
      for (final group in groups) {
        expect(group.list, isNotEmpty, reason: '${group.title} 榜单为空');
        for (final item in group.list) {
          expect(item.hid, isNotEmpty);
          expect(item.title, isNotEmpty);
          expect(item.cover, startsWith('http'));
        }
      }
    });

    test('同一榜单内 hid 不重复', () {
      for (final group in groups) {
        final ids = group.list.map((e) => e.hid).toList();
        expect(ids.toSet().length, ids.length);
      }
    });
  });
}
