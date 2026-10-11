import 'package:get/get.dart';
import 'package:tucao/utils/storage_pref.dart';

/// 主题设置.
class ThemeService extends GetxController {
  static ThemeService get instance => Get.find<ThemeService>();

  /// 0 跟随系统, 1 浅色, 2 深色.
  final themeMode = Pref.themeMode.obs;

  /// 主题种子色, 为空表示使用站点默认色.
  final seedColor = Pref.themeColor.obs;

  /// 是否使用系统取色.
  final useDynamicColor = Pref.dynamicColor.obs;

  void setThemeMode(int value) {
    themeMode.value = value;
    Pref.themeMode = value;
  }

  void setSeedColor(int? value) {
    seedColor.value = value;
    Pref.themeColor = value;
  }

  void setDynamicColor(bool value) {
    useDynamicColor.value = value;
    Pref.dynamicColor = value;
  }
}
