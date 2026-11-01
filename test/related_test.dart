import 'package:flutter_test/flutter_test.dart';
import 'package:tucao/models/video.dart';
import 'package:tucao/services/related/related_ranker.dart';
import 'package:tucao/services/related/series_parser.dart';

void main() {
  group('作品名提取', () {
    test('去掉方括号段, 拆出中英文别名', () {
      expect(SeriesParser.parseAliases('【無修】缘之空 Yosuga no Sora【澄空学园】'), [
        '缘之空',
        'Yosuga no Sora',
      ]);
      expect(SeriesParser.parseAliases('SPY×FAMILY / 间谍过家家 22【桜都】'), [
        'SPY×FAMILY',
        '间谍过家家',
      ]);
    });

    test('在季数, 剧场版与集数范围处截断', () {
      expect(SeriesParser.parseAliases('【合集】进击的巨人 第四季 【01-29】【特别篇】'), [
        '进击的巨人',
      ]);
      expect(SeriesParser.parseAliases('【BD1080p】火影忍者剧场版11.博人传【日语】'), ['火影忍者']);
      expect(SeriesParser.parseAliases('【猪猪】火影忍者 naruto【1-200】'), [
        '火影忍者',
        'naruto',
      ]);
    });

    test('剥掉中文名后的罗马数字, 字母与数字续作标记', () {
      // 带着标记搜索只能搜到这一季, 也对不上其他季的标题.
      for (final title in [
        '【TVRIP/720P】魔法禁书目录Ⅲ【第3季】',
        '『低画质』魔法禁书目录II+特典『1……24话』',
        '魔法禁书目录 III 01',
      ]) {
        expect(SeriesParser.parseAliases(title), ['魔法禁书目录'], reason: title);
      }
      expect(SeriesParser.parseAliases('【1月】某科学的超电磁炮T 14'), ['某科学的超电磁炮']);
      expect(SeriesParser.parseAliases('物语系列01 化物语【1-15】'), ['物语系列', '化物语']);
      expect(SeriesParser.parseAliases('『生肉』化物语15话'), ['化物语']);
      // 较长的英文尾巴是别名, 不是标记.
      expect(SeriesParser.parseAliases('缘之空Yosuga'), ['缘之空', 'Yosuga']);
    });
  });

  group('季解析', () {
    test('中文数字, S 前缀, 最终季与前后篇', () {
      final s4 = SeriesParser.parse('Re：从零开始的异世界生活 第四季');
      expect((s4.kind, s4.season), (SeriesKind.tv, 4));
      expect(SeriesParser.parse('【BDRIP/1080P】进击的巨人 S2').season, 2);
      final last = SeriesParser.parse('进击的巨人 最终季 完结篇 后篇(91-94)');
      expect((last.season, last.part), (SeriesParser.finalSeason, 2));
      // 画质里的 1080P 不能被当成季数.
      expect(SeriesParser.parse('缘之空 1080P').season, isNull);
    });

    test('罗马数字记成季数, 剧场版里的记成第几部', () {
      expect(SeriesParser.parse('【10月】魔法禁书目录Ⅲ 09【桜都】').season, 3);
      final movie = SeriesParser.parse('【剧场版】伤物语 Ⅰ 铁血篇');
      expect((movie.season, movie.variant), (null, '001'));
      expect(SeriesParser.parse('【剧场版】伤物语1：铁血篇').variant, movie.variant);
    });
  });

  group('相关视频排序', () {
    VideoModel video(
      String hid,
      String title, {
      int play = 0,
      int typeId = 0,
    }) => VideoModel(hid: hid, title: title, playCount: play, typeId: typeId);

    test('同系列按季序排在前, 去重并去掉当前视频', () {
      final current = video('3', '【合集】进击的巨人 第三季 【01-22】');
      final ranked = RelatedRanker.rank(current, [
        video('9', '【MAD】某个无关的视频', play: 999999),
        video('99', '进击的巨人 最终季 第01集', play: 10),
        video('2', '【合集】进击的巨人 第二季', play: 5),
        video('3', '【合集】进击的巨人 第三季 【01-22】'),
        video('m', '【剧场版】进击的巨人 自由之翼', play: 50000, typeId: 26),
        video('1', '【合集】进击的巨人 01~26集', play: 100),
        video('2', '【合集】进击的巨人 第二季', play: 5),
      ]);
      expect(ranked.map((e) => e.video.hid), ['1', '2', '99', 'm', '9']);
      expect(ranked.last.sameSeries, isFalse);
    });

    test('有整季投稿时去掉单集, 只有单集时留最小一集', () {
      final current = video('c', '【合集】进击的巨人 第三季 【01-22】');
      final ranked = RelatedRanker.rank(current, [
        video('s1', '【合集】进击的巨人 01~26集', play: 10),
        video('s1e3', '【4月】进击的巨人 03【Dymy】', play: 900),
        video('s2e2', '【4月】进击的巨人 第二季 02【动漫国】', play: 800),
        video('s2e1', '【4月】进击的巨人 第二季 01【动漫国】', play: 700),
        video('s2e5', '【4月】进击的巨人 第二季 05【动漫国】', play: 600),
      ]);
      expect(ranked.map((e) => e.video.hid), ['s1', 's2e1']);
    });

    test('只写续作标记的单集按同标记的整季补上季数', () {
      final current = video('c', '【2009新番】某科学的超电磁炮【第1季】');
      final ranked = RelatedRanker.rank(current, [
        video('t', '【2020新番】某科学的超电磁炮T【1-25】【第3季】'),
        video('se1', '【4月】某科学的超电磁炮S 01【DYMY】', play: 900),
        video('s1', '【合集】某科学的超电磁炮 01-24'),
      ]);
      // 第 1 季的合集不能把 S 的单集收掉; S 没有整季投稿, 留下单集作为入口.
      expect(ranked.map((e) => e.video.hid), ['s1', 'se1', 't']);
      expect(ranked[1].series.season, isNull);

      final filled = RelatedRanker.rank(current, [
        video('s2', '【2012新番】某科学的超电磁炮S【24全】【第2季】'),
        video('se1', '【4月】某科学的超电磁炮S 01【DYMY】', play: 900),
      ]);
      // S 有了第 2 季的整季投稿, 单集补上季数后被收掉.
      expect(filled.map((e) => e.video.hid), ['s2']);
    });
  });
}
