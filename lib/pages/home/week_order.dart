import 'package:tucao/models/video.dart';
import 'package:tucao/models/week_update_time.dart';

/// 时间表卡片的展示顺序.
///
/// 更新时刻要逐部请求播放页, 每到一条就重排会让卡片来回跳. 这里在本组
/// 数据没到齐时把顺序定住, 到齐后只换一次; 等太久时调用方可以 [flush]
/// 先按已有数据排一次, 之后照样定住, 到齐再排最后一次.
///
/// 定住期间列表内容变了 (屏蔽, 刷新出新番) 也不重排: 消失的卡片直接去掉,
/// 新出现的接在末尾.
class WeekOrderGate {
  String? _group;

  /// 当前展示的顺序, 存 hid.
  List<String> _shown = const [];

  /// 本组数据已经到齐过, 之后顺序直接跟随排序结果.
  bool _released = false;

  bool _flushPending = false;

  /// 按本组最新的排序结果 [arranged] 给出这一帧的展示顺序.
  ///
  /// [ready] 表示排序依赖的数据都已有结果. 切到另一组时重新开始, 这时
  /// 用当下的排序结果做起点, 已经取齐的分组切回来不会再动.
  List<VideoModel> resolve({
    required String group,
    required List<VideoModel> arranged,
    required bool ready,
  }) {
    if (_group != group) {
      _group = group;
      _released = false;
      _flushPending = false;
      _shown = [for (final video in arranged) video.hid];
    }
    if (ready) {
      _released = true;
    }
    if (_released || _flushPending) {
      _flushPending = false;
      _shown = [for (final video in arranged) video.hid];
      return arranged;
    }
    final byHid = {for (final video in arranged) video.hid: video};
    final kept = [
      for (final hid in _shown)
        if (byHid.containsKey(hid)) byHid[hid]!,
    ];
    final keptHids = {for (final video in kept) video.hid};
    final result = [
      ...kept,
      for (final video in arranged)
        if (!keptHids.contains(video.hid)) video,
    ];
    _shown = [for (final video in result) video.hid];
    return result;
  }

  /// 下一次 [resolve] 时按当时的排序结果排一次, 之后继续定住.
  ///
  /// 只对 [group] 生效, 计时期间已经切走的分组不受影响.
  void flush(String group) {
    if (_group == group && !_released) {
      _flushPending = true;
    }
  }
}

/// 已追的番排在前面, 排序开启时两部分内部再按更新时刻升序.
///
/// 没有时刻的番剧排在所在部分的最后, 彼此之间保持站点原来的顺序.
List<VideoModel> arrangeWeekItems(
  List<VideoModel> list, {
  required Set<String> followed,
  required Map<String, WeekUpdateTime> times,
  required bool sortByTime,
}) {
  final followedList = <VideoModel>[];
  final rest = <VideoModel>[];
  for (final video in list) {
    (followed.contains(video.hid) ? followedList : rest).add(video);
  }
  if (!sortByTime) {
    return [...followedList, ...rest];
  }
  return [
    ...sortByUpdateTime(followedList, times),
    ...sortByUpdateTime(rest, times),
  ];
}

/// 按更新时刻升序, 没有时刻的排在后面, 时刻相同时保持站点顺序.
///
/// `List.sort` 不保证稳定, 因此用原下标兜底.
List<VideoModel> sortByUpdateTime(
  List<VideoModel> list,
  Map<String, WeekUpdateTime> times,
) {
  final indexed = list.indexed.toList();
  indexed.sort((a, b) {
    final left = times[a.$2.hid]?.minutesOfDay;
    final right = times[b.$2.hid]?.minutesOfDay;
    if (left == null && right == null) {
      return a.$1 - b.$1;
    }
    if (left == null) {
      return 1;
    }
    if (right == null) {
      return -1;
    }
    if (left != right) {
      return left - right;
    }
    return a.$1 - b.$1;
  });
  return [for (final (_, video) in indexed) video];
}
