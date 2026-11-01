import 'package:flutter_test/flutter_test.dart';
import 'package:tucao/models/video.dart';
import 'package:tucao/models/week_update_time.dart';
import 'package:tucao/pages/home/week_order.dart';

VideoModel _video(String hid) => VideoModel(hid: hid, title: hid);

WeekUpdateTime _at(int hour, int minute) =>
    WeekUpdateTime(hour: hour, minute: minute);

void main() {
  group('更新时刻解析', () {
    test('从站点文案里取时分', () {
      expect(WeekUpdateTime.parse('星期天，01:50')?.label, '01:50');
      expect(WeekUpdateTime.parse('星期六 ， 11:30')?.label, '11:30');
      expect(WeekUpdateTime.parse('更新：星期一, 9:05')?.label, '09:05');
    });

    test('非法或缺失的文案返回 null', () {
      // 剧场版与部分天朝番没有这一项, 页面里根本不给文案.
      expect(WeekUpdateTime.parse(''), isNull);
      expect(WeekUpdateTime.parse('星期天'), isNull);
      expect(WeekUpdateTime.parse('25:00'), isNull);
      expect(WeekUpdateTime.parse('01:60'), isNull);
    });

    test('分钟数用于排序', () {
      expect(_at(1, 50).minutesOfDay, 110);
      expect(_at(0, 0).minutesOfDay, 0);
    });

    test('当天的时刻到过之后算可看', () {
      final time = _at(20, 2);
      expect(time.hasReached(DateTime(2026, 11, 1, 20, 1)), isFalse);
      expect(time.hasReached(DateTime(2026, 11, 1, 20, 2)), isTrue);
      expect(time.hasReached(DateTime(2026, 11, 1, 23, 59)), isTrue);
      expect(time.hasReached(DateTime(2026, 11, 1, 0, 0)), isFalse);
    });
  });

  group('时间表排序', () {
    test('按更新时刻升序, 没有时刻的排在最后', () {
      final items = [_video('a'), _video('b'), _video('c'), _video('d')];
      final times = {'a': _at(23, 0), 'b': _at(1, 50), 'd': _at(12, 30)};
      final sorted = sortByUpdateTime(items, times);
      expect(sorted.map((e) => e.hid).toList(), ['b', 'd', 'a', 'c']);
    });

    test('时刻相同时保持站点顺序', () {
      final items = [_video('a'), _video('b'), _video('c')];
      final times = {'a': _at(9, 0), 'b': _at(9, 0), 'c': _at(9, 0)};
      expect(sortByUpdateTime(items, times).map((e) => e.hid).toList(), [
        'a',
        'b',
        'c',
      ]);
    });

    test('已追仍置顶, 两部分各自按时刻排', () {
      final items = [_video('a'), _video('b'), _video('c'), _video('d')];
      final times = {
        'a': _at(23, 0),
        'b': _at(1, 0),
        'c': _at(12, 0),
        'd': _at(8, 0),
      };
      final arranged = arrangeWeekItems(
        items,
        followed: {'a', 'c'},
        times: times,
        sortByTime: true,
      );
      expect(arranged.map((e) => e.hid).toList(), ['c', 'a', 'b', 'd']);
    });

    test('关闭排序时只做已追置顶', () {
      final items = [_video('a'), _video('b'), _video('c')];
      final arranged = arrangeWeekItems(
        items,
        followed: {'b'},
        times: {'a': _at(23, 0), 'b': _at(1, 0)},
        sortByTime: false,
      );
      expect(arranged.map((e) => e.hid).toList(), ['b', 'a', 'c']);
    });

    test('没有可排序的时刻时保持原顺序', () {
      final arranged = arrangeWeekItems(
        [_video('a'), _video('b')],
        followed: <String>{},
        times: const {},
        sortByTime: true,
      );
      expect(arranged.map((e) => e.hid).toList(), ['a', 'b']);
    });
  });

  group('时间表顺序闸门', () {
    List<String> hids(List<VideoModel> list) => [for (final e in list) e.hid];

    test('到齐前定住顺序, 到齐后只换一次', () {
      final gate = WeekOrderGate();
      final a = _video('a'), b = _video('b'), c = _video('c');
      expect(
        hids(gate.resolve(group: 'g', arranged: [a, b, c], ready: false)),
        ['a', 'b', 'c'],
      );
      // 时刻陆续到达, 排序结果变了也先不动.
      expect(
        hids(gate.resolve(group: 'g', arranged: [c, a, b], ready: false)),
        ['a', 'b', 'c'],
      );
      expect(
        hids(gate.resolve(group: 'g', arranged: [c, b, a], ready: true)),
        ['c', 'b', 'a'],
      );
    });

    test('定住期间去掉消失的, 新出现的接在末尾', () {
      final gate = WeekOrderGate();
      final a = _video('a'), b = _video('b'), c = _video('c'), d = _video('d');
      gate.resolve(group: 'g', arranged: [a, b, c], ready: false);
      expect(
        hids(gate.resolve(group: 'g', arranged: [d, c, a], ready: false)),
        ['a', 'c', 'd'],
      );
    });

    test('超时兜底排一次后继续定住', () {
      final gate = WeekOrderGate();
      final a = _video('a'), b = _video('b'), c = _video('c');
      gate.resolve(group: 'g', arranged: [a, b, c], ready: false);
      // 切走的分组不受兜底影响.
      gate.flush('other');
      expect(
        hids(gate.resolve(group: 'g', arranged: [b, a, c], ready: false)),
        ['a', 'b', 'c'],
      );
      gate.flush('g');
      expect(
        hids(gate.resolve(group: 'g', arranged: [b, a, c], ready: false)),
        ['b', 'a', 'c'],
      );
      expect(
        hids(gate.resolve(group: 'g', arranged: [c, b, a], ready: false)),
        ['b', 'a', 'c'],
      );
    });
  });
}
