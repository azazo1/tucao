import 'package:screen_brightness/screen_brightness.dart';
import 'package:tucao/utils/logger.dart';

/// 播放页的画面亮度, 只改本应用窗口, 不动系统设置.
///
/// 手势层只依赖这个接口, 测试里可以换成内存实现.
abstract class PlayerBrightness {
  /// 当前亮度, 0 到 1. 读取失败时返回 null.
  Future<double?> current();

  Future<void> set(double value);

  /// 交还给系统亮度, 离开播放页时调用.
  Future<void> reset();
}

/// 基于 screen_brightness 插件的实现, 平台调用失败只记日志.
class ScreenPlayerBrightness implements PlayerBrightness {
  const ScreenPlayerBrightness();

  ScreenBrightness get _plugin => ScreenBrightness.instance;

  @override
  Future<double?> current() async {
    try {
      return await _plugin.application;
    } catch (error) {
      Log.w('读取画面亮度失败: $error');
      return null;
    }
  }

  @override
  Future<void> set(double value) async {
    try {
      await _plugin.setApplicationScreenBrightness(value.clamp(0.0, 1.0));
    } catch (error) {
      Log.w('设置画面亮度失败: $error');
    }
  }

  @override
  Future<void> reset() async {
    try {
      if (await _plugin.hasApplicationScreenBrightnessChanged) {
        await _plugin.resetApplicationScreenBrightness();
        Log.i('画面亮度恢复为系统亮度');
      }
    } catch (error) {
      Log.w('恢复系统亮度失败: $error');
    }
  }
}
