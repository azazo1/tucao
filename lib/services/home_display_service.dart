import 'package:get/get.dart';
import 'package:tucao/utils/storage_pref.dart';

/// 首页上两块内容的显示开关.
///
/// 公告顶幅挂在顶栏的 bottom 里, 继续观看卡片挂在时间表顶部, 两者都由首页
/// 自己判断是否出现. 设置页改动后首页不需要重建就能跟着收起或展开,
/// 因此状态放在 Rx 里, 由使用方在 Obx 中读取.
class HomeDisplayService extends GetxController {
  static HomeDisplayService get instance => Get.find<HomeDisplayService>();

  /// 是否显示公告顶幅.
  final showNotice = Pref.showHomeNotice.obs;

  /// 是否显示继续观看卡片.
  final showContinueWatching = Pref.showContinueWatching.obs;

  void setShowNotice(bool value) {
    if (showNotice.value == value) {
      return;
    }
    showNotice.value = value;
    Pref.showHomeNotice = value;
  }

  void setShowContinueWatching(bool value) {
    if (showContinueWatching.value == value) {
      return;
    }
    showContinueWatching.value = value;
    Pref.showContinueWatching = value;
  }
}
