import 'package:get/get.dart';
import 'package:tucao/utils/storage_pref.dart';

/// 弹幕高能条开关.
///
/// 设置页的开关与正在播放的视频共用这一个状态: 改动后播放页立即显示或收起
/// 进度条上方的密度图, 不必重新进入播放页.
class DanmakuTrendService extends GetxController {
  static DanmakuTrendService get instance => Get.find<DanmakuTrendService>();

  /// 服务未注册时返回空, 便于测试里只构造播放页控制器.
  static DanmakuTrendService? get maybe =>
      Get.isRegistered<DanmakuTrendService>()
      ? Get.find<DanmakuTrendService>()
      : null;

  final enabled = Pref.danmakuTrend.obs;

  void setEnabled(bool value) {
    if (enabled.value == value) {
      return;
    }
    enabled.value = value;
    Pref.danmakuTrend = value;
  }
}
