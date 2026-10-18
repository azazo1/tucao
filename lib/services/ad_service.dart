import 'package:get/get.dart';
import 'package:tucao/utils/storage_pref.dart';

/// 广告入口开关.
///
/// 首页按钮与设置页开关共用这一个状态, 广告页里的"取消广告"也走这里,
/// 任一入口改动后其余位置立即同步.
class AdService extends GetxController {
  static AdService get instance => Get.find<AdService>();

  final enabled = Pref.showAdEntry.obs;

  void setEnabled(bool value) {
    if (enabled.value == value) {
      return;
    }
    enabled.value = value;
    Pref.showAdEntry = value;
  }
}
