import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tucao/http/bgm_http.dart';

void main() {
  group('番组索引解析', () {
    late List<dynamic> list;

    setUpAll(() {
      final raw = File('test/fixtures/bgm_index.html').readAsStringSync();
      list = BgmHttp.parseBgmHtml(raw);
    });

    test('解析出番组条目', () {
      expect(list, isNotEmpty);
      for (final item in list) {
        expect(item.hid, isNotEmpty);
        expect(item.title, isNotEmpty);
        expect(item.cover, contains('tucao.my'));
      }
    });

    test('hid 不重复', () {
      final ids = list.map((e) => e.hid).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('解析出集数状态与题材标签', () {
      // 站点把集数状态与题材放在卡片下方的补充行里,
      // 解析时分别写进 description 与 keywords.
      final withState = list.where(
        (e) => e.description.isNotEmpty || e.keywords.isNotEmpty,
      );
      expect(withState, isNotEmpty);
    });

    test('筛选参数与站点一致', () {
      // 季度用的是站点的 month 取值, 剧场版固定为 99.
      expect(BgmHttp.seasonOptions['10月'], 10);
      expect(BgmHttp.seasonOptions['剧场版'], 99);
      // 年代包含区间与逐年两项.
      expect(BgmHttp.yearOptions, contains('1906-1999'));
      expect(BgmHttp.yearOptions, contains('2026'));
      // 星期用 1-6 表示周一到周六, 7 表示周日.
      expect(BgmHttp.weekdayOptions['星期一'], 1);
      expect(BgmHttp.weekdayOptions['星期六'], 6);
      expect(BgmHttp.weekdayOptions['星期日'], 7);
      expect(BgmHttp.weekdayOptions, hasLength(7));
    });

    test('空页面返回空列表而不是抛异常', () {
      expect(BgmHttp.parseBgmHtml('<html></html>'), isEmpty);
    });
  });
}
