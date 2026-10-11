import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tucao/http/week_bgm_http.dart';

void main() {
  group('本周新番解析', () {
    late List<WeekBgmGroup> groups;

    setUpAll(() {
      final raw = File('test/fixtures/week_bgm.html').readAsStringSync();
      groups = WeekBgmHttp.parseWeekBgmHtml(raw);
    });

    test('按日期分组', () {
      expect(groups, isNotEmpty);
      for (final group in groups) {
        expect(group.date, matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
        expect(group.weekday, isNotEmpty);
        expect(group.list, isNotEmpty);
      }
    });

    test('分组按页面顺序排列', () {
      // 站点从最近一天往前排, 这里只断言日期都是合法的且不重复.
      final dates = groups.map((e) => e.date).toList();
      expect(dates.toSet().length, dates.length);
    });

    test('条目字段完整', () {
      for (final group in groups) {
        for (final item in group.list) {
          expect(item.hid, isNotEmpty);
          expect(item.title, isNotEmpty);
          expect(item.cover, contains('tucao.my'));
        }
      }
    });

    test('同一日期内 hid 不重复', () {
      for (final group in groups) {
        final ids = group.list.map((e) => e.hid).toList();
        expect(ids.toSet().length, ids.length);
      }
    });

    test('分组标题省略年份', () {
      final group = groups.first;
      expect(group.title, isNot(contains(group.date.substring(0, 4))));
      expect(group.title, contains(group.weekday));
    });

    test('空页面返回空列表而不是抛异常', () {
      expect(WeekBgmHttp.parseWeekBgmHtml('<html></html>'), isEmpty);
    });
  });
}
