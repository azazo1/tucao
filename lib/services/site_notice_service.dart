import 'dart:async';

import 'package:get/get.dart';
import 'package:tucao/http/site_notice_http.dart';
import 'package:tucao/utils/logger.dart';
import 'package:tucao/utils/storage_pref.dart';

/// 首页站务文章与已读状态.
///
/// 时间表上方的通知条只轮换没看过的文章, 关掉通知条或点开铃铛就算看过,
/// 站点发了新文章才会再出现. 已读编号写进配置, 只保留最近 [maxSeen] 条,
/// 轮转区一般只有几篇, 早已下架的编号不必一直留着.
class SiteNoticeService extends GetxController {
  static SiteNoticeService get instance => Get.find<SiteNoticeService>();

  static const maxSeen = 50;

  final notices = <SiteNotice>[].obs;

  final _seen = <String>{}.obs;

  bool _loading = false;

  /// 没看过的文章, 保持页面顺序.
  List<SiteNotice> get unread => unreadOf(notices, _seen);

  bool isSeen(String hid) => _seen.contains(hid);

  @override
  void onInit() {
    super.onInit();
    _seen.addAll(Pref.seenSiteNotices);
    unawaited(load());
  }

  /// 拉取一次轮转区, 失败时保留上一次的结果.
  Future<void> load() async {
    if (_loading) {
      return;
    }
    _loading = true;
    try {
      notices.assignAll(await SiteNoticeHttp.fetch());
    } catch (e, stackTrace) {
      Log.e('加载首页站务文章失败', error: e, stackTrace: stackTrace);
    } finally {
      _loading = false;
    }
  }

  void markSeen(String hid) => _remember([hid]);

  /// 关掉通知条或打开全部列表时调用, 当前所有文章都算看过.
  void markAllSeen() => _remember(notices.map((item) => item.hid));

  void _remember(Iterable<String> hids) {
    final added = hids.where((hid) => !_seen.contains(hid)).toList();
    if (added.isEmpty) {
      return;
    }
    _seen.addAll(added);
    final kept = trimSeen([...Pref.seenSiteNotices, ...added]);
    Pref.seenSiteNotices = kept;
    Log.i('站务文章标记已读 ${added.length} 条, 共记录 ${kept.length} 条');
  }

  static List<SiteNotice> unreadOf(
    Iterable<SiteNotice> notices,
    Set<String> seen,
  ) {
    return notices.where((item) => !seen.contains(item.hid)).toList();
  }

  /// 去重后只留最近的 [maxSeen] 条, 新的在后.
  static List<String> trimSeen(List<String> hids) {
    final unique = <String>[];
    for (final hid in hids.reversed) {
      if (!unique.contains(hid)) {
        unique.add(hid);
      }
      if (unique.length >= maxSeen) {
        break;
      }
    }
    return unique.reversed.toList();
  }
}
