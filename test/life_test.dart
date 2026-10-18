import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tucao/http/life_http.dart';
import 'package:tucao/models/life.dart';

void main() {
  group('续命数据解析', () {
    test('解析会员中心的存活天数与会员数值', () {
      final raw = File('test/fixtures/member_life.html').readAsStringSync();
      final status = LifeHttp.parseStatusHtml(raw);

      expect(status, isNotNull);
      expect(status!.survivalDays, 7.85);
      expect(status.myDays, 12.5);
      expect(status.contributors, hasLength(3));
      // 头像有相对路径, 解析后都要是绝对地址.
      for (final url in status.contributors) {
        expect(url, startsWith('http'));
      }
      expect(status.member.groupName, '1元1次');
      expect(status.member.credit, 11);
      expect(status.member.guardDays, 12.5);
      expect(status.member.residentYears, 2);
    });

    test('未登录时的会话过期页面返回 null', () {
      final status = LifeHttp.parseStatusHtml(
        '<html><body>您的会话已过期，请重新登录。</body></html>',
      );
      expect(status, isNull);
    });

    test('解析贡献榜条目', () {
      final raw = File('test/fixtures/life_rank.html').readAsStringSync();
      final rank = LifeHttp.parseRankHtml(raw);

      expect(rank.requiresLogin, isFalse);
      expect(rank.sourceArticleId, '7130');
      expect(rank.items, hasLength(5));

      final first = rank.items.first;
      expect(first.rank, 1);
      expect(first.userName, '示例甲');
      expect(first.days, 5.49);
      expect(first.ratio, 1.52);
      expect(first.avatar, startsWith('http'));

      expect(rank.items.map((e) => e.rank), [1, 2, 3, 4, 5]);
      // 纯数字昵称不能被当成续命天数.
      expect(rank.items.last.userName, '13452109040');
      expect(rank.items.last.days, 0.1);
      // 站点给的占比与文案里的天数不一定同步, 两者各自解析.
      expect(rank.items[3].days, 0.37);
      expect(rank.items[3].ratio, 0.19);
    });

    test('未登录的贡献榜标记为需要登录', () {
      final rank = LifeHttp.parseRankHtml('您的会话已过期，请重新登录。');
      expect(rank.requiresLogin, isTrue);
      expect(rank.items, isEmpty);
    });

    test('空页面不抛异常', () {
      expect(LifeHttp.parseStatusHtml(''), isNull);
      final rank = LifeHttp.parseRankHtml('');
      expect(rank.items, isEmpty);
      expect(rank.requiresLogin, isTrue);
    });
  });

  group('续命天数文案', () {
    test('整数不带小数点, 小数最多两位', () {
      expect(formatLifeDays(0), '0');
      expect(formatLifeDays(7.85), '7.85');
      expect(formatLifeDays(12.5), '12.5');
      expect(formatLifeDays(0.1), '0.1');
      expect(formatLifeDays(5.49), '5.49');
    });
  });
}
