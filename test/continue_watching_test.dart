import 'package:flutter_test/flutter_test.dart';
import 'package:tucao/models/video.dart';
import 'package:tucao/pages/home/widgets/continue_watching_banner.dart';
import 'package:tucao/services/history_service.dart';

HistoryItem _item(String hid, double progress, DateTime at) => HistoryItem(
  video: VideoModel(hid: hid, title: hid),
  part: 0,
  progress: progress,
  duration: 100,
  updateTime: at.millisecondsSinceEpoch,
);

void main() {
  test('继续观看跳过看完与只点开过的记录, 过期记录不再提示', () {
    final now = DateTime(2026, 10, 31, 20);
    final history = [
      _item('done', 95, now),
      _item('peek', 1, now.subtract(const Duration(hours: 1))),
      _item('half', 50, now.subtract(const Duration(days: 1))),
      _item('old', 50, now.subtract(const Duration(days: 8))),
    ];
    expect(
      ContinueWatchingBanner.pickAll(history, now).map((e) => e.video.hid),
      ['half'],
    );
    expect(ContinueWatchingBanner.pickAll(history.sublist(3), now), isEmpty);
  });

  test('继续观看多条时同一视频只留最新一条, 且不超过上限', () {
    final now = DateTime(2026, 10, 31, 20);
    final history = [
      _item('a', 30, now),
      _item('a', 60, now.subtract(const Duration(hours: 1))),
      for (var i = 0; i < ContinueWatchingBanner.maxItems + 2; i++)
        _item('v$i', 40, now.subtract(Duration(hours: 2 + i))),
    ];
    final picked = ContinueWatchingBanner.pickAll(history, now);
    expect(picked.length, ContinueWatchingBanner.maxItems);
    expect(picked.first.video.hid, 'a');
    expect(picked.first.progress, 30);
    expect(picked.where((e) => e.video.hid == 'a').length, 1);
  });
}
