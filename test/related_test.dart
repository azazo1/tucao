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
  });
}
