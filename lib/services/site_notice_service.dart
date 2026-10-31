import 'dart:async';

import 'package:get/get.dart';
import 'package:tucao/http/site_notice_http.dart';
import 'package:tucao/utils/logger.dart';

/// 首页站务文章.
///
/// 首页主标签栏上方的通知卡片轮换这些文章. 关掉卡片只在本次运行内有效,
/// 不写配置, 下次启动重新显示.
class SiteNoticeService extends GetxController {
  static SiteNoticeService get instance => Get.find<SiteNoticeService>();

  final notices = <SiteNotice>[].obs;

  /// 本次运行内是否关掉了通知卡片.
  final dismissed = false.obs;

  bool _loading = false;

  /// 是否显示通知卡片, 在 Obx 里读取才会跟着变化.
  bool get visible => !dismissed.value && notices.isNotEmpty;

  @override
  void onInit() {
    super.onInit();
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

  void dismiss() {
    Log.i('关闭首页通知卡片, 本次运行内不再显示');
    dismissed.value = true;
  }
}
