import 'dart:async';

import 'package:get/get.dart';
import 'package:tucao/http/video_http.dart';
import 'package:tucao/models/week_update_time.dart';
import 'package:tucao/utils/logger.dart';

/// 时间表里各番剧的更新时刻.
///
/// 站点只在播放页的番组信息里给出时刻, 首页时间表没有, 因此这里对当前
/// 分组里的番剧逐个取播放页. 结果只留在内存里, 不落盘; 顺带把播放页
/// 详情写进 `VideoHttp` 的缓存, 用户点进视频页时不必再请求同一个页面.
class WeekUpdateTimeService extends GetxController {
  static WeekUpdateTimeService get instance =>
      Get.find<WeekUpdateTimeService>();

  /// 同时请求的番剧数, 站点页面较大, 不宜一次发太多.
  static const maxConcurrent = 4;

  /// 已取到时刻的番剧, 键是 hid.
  ///
  /// 用 RxMap 而不是普通 Map, 界面在 Obx 里读到时就会订阅, 每取到一条
  /// 时刻就补上角标.
  final times = <String, WeekUpdateTime>{}.obs;

  /// 这一轮请求已有结果的番剧: 取到时刻, 确认没有, 或请求失败都算.
  ///
  /// 时间表靠它判断本组是否到齐, 到齐前不重排. 失败的番再次排队时会被
  /// 移出, 等新的结果.
  final settled = <String>{}.obs;

  /// 取过但播放页里没有更新时刻的番剧, 不再重复请求.
  final _missing = <String>{};

  /// 正在请求或排队中的番剧.
  final _pending = <String>{};

  final _queue = <String>[];

  int _running = 0;

  /// 取时刻, 已有的和取过没有的都会跳过, 可以反复调用.
  void ensure(Iterable<String> hids) {
    var added = false;
    for (final hid in hids) {
      if (times.containsKey(hid) ||
          _missing.contains(hid) ||
          _pending.contains(hid)) {
        continue;
      }
      _pending.add(hid);
      _queue.add(hid);
      settled.remove(hid);
      added = true;
    }
    if (added) {
      _pump();
    }
  }

  void _pump() {
    while (_running < maxConcurrent && _queue.isNotEmpty) {
      final hid = _queue.removeAt(0);
      _running++;
      unawaited(_fetch(hid));
    }
  }

  Future<void> _fetch(String hid) async {
    try {
      // 播放页同时带简介与番组信息, 这里的请求也会填进 VideoHttp 的缓存.
      final page = await VideoHttp.fetchPlayPage(hid: hid);
      // 整块番组信息都没有时多半是临时错误, 不记进 missing, 留待下次重试.
      if (page.subject.isEmpty) {
        Log.w('播放页没有番组信息: $hid');
        return;
      }
      final time = WeekUpdateTime.parse(page.subject.valueOf('更新'));
      if (time == null) {
        // 剧场版与部分天朝番本来就没有更新时刻, 不必再问.
        _missing.add(hid);
      } else {
        times[hid] = time;
      }
    } catch (e) {
      // 失败不记进 missing, 下次进入分组时会重试.
      Log.w('取番剧更新时刻失败: $hid, $e');
    } finally {
      _pending.remove(hid);
      settled.add(hid);
      _running--;
      _pump();
    }
  }
}
