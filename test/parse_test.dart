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

  group('其它榜单解析', () {
    /// 弹幕榜, 神评论与追番榜与排行榜同结构, 都是四个时间维度.
    for (final name in ['danmu', 'digg', 'fav_hot']) {
      test('$name 解析出四个时间维度且条目完整', () {
        final raw = File('test/fixtures/rank_$name.html').readAsStringSync();
        final groups = RankHttp.parseRankHtml(raw);
        expect(groups.map((e) => e.title).toList(), ['今天', '本周', '本月', '今年']);
        for (final group in groups) {
          expect(group.list, isNotEmpty);
          for (final item in group.list) {
            expect(item.hid, isNotEmpty);
            expect(item.title, isNotEmpty);
            expect(item.cover, startsWith('http'));
          }
        }
      });
    }

    test('无人区按分区分组, 分组名不是时间维度', () {
      final raw = File('test/fixtures/rank_zero.html').readAsStringSync();
      final groups = RankHttp.parseRankHtml(raw);
      expect(groups, isNotEmpty);
      // 分组名不是今天/本周这类时间文案, period 统一记为 -1.
      for (final group in groups) {
        expect(group.period, -1, reason: '${group.title} 不应被当成时间维度');
        expect(group.list, isNotEmpty);
      }
    });

    test('在线榜没有分组容器, 整页作为一组', () {
      final raw = File('test/fixtures/rank_ol.html').readAsStringSync();
      final groups = RankHttp.parseRankHtml(raw);
      expect(groups, hasLength(1));
      expect(groups.first.list, isNotEmpty);
      expect(groups.first.period, -1);
      for (final item in groups.first.list) {
        expect(item.hid, isNotEmpty);
        expect(item.title, isNotEmpty);
        expect(item.cover, startsWith('http'));
      }
    });

    // 今天更新与今天推荐也是单列表结构, 与在线榜同型.
    for (final name in ['new', 'pos']) {
      test('$name 单列表页整页作为一组', () {
        final raw = File('test/fixtures/rank_$name.html').readAsStringSync();
        final groups = RankHttp.parseRankHtml(raw);
        expect(groups, hasLength(1));
        expect(groups.first.period, -1);
        expect(groups.first.list, isNotEmpty);
        for (final item in groups.first.list) {
          expect(item.hid, isNotEmpty);
          expect(item.title, isNotEmpty);
          expect(item.cover, contains('tucao.my'));
        }
      });
    }

    test('热搜榜解析出关键词与搜索次数', () {
      final raw = File('test/fixtures/rank_hot_search.html').readAsStringSync();
      final list = RankHttp.parseHotSearchHtml(raw);
      expect(list, isNotEmpty);
      for (final item in list) {
        expect(item.keyword, isNotEmpty);
        expect(item.rank, greaterThan(0));
        expect(item.count, greaterThan(0));
      }
      // 排名应当从 1 开始递增.
      expect(list.first.rank, 1);
    });
  });
}
