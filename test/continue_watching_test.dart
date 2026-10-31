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
    expect(ContinueWatchingBanner.pick(history, now)?.video.hid, 'half');
    expect(ContinueWatchingBanner.pick(history.sublist(3), now), isNull);
  });
}
