import 'package:flutter_test/flutter_test.dart';
import 'package:tucao/models/video.dart';
import 'package:tucao/models/week_update_time.dart';
import 'package:tucao/pages/home/week_view.dart';

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
}
