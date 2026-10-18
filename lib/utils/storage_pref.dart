import 'package:tucao/common/constants.dart';
import 'package:tucao/utils/danmaku_preferences_store.dart';
import 'package:tucao/utils/storage.dart';

/// 用户偏好的读写封装.
///
/// 所有键都带默认值, 首次运行时不会读到空值.
abstract final class Pref {
  static const _kThemeMode = 'theme_mode';
  static const _kThemeColor = 'theme_color';
  static const _kDynamicColor = 'dynamic_color';
  static const _kPlayerSpeed = 'player_speed';
  static const _kPlayerVolume = 'player_volume';
  static const _kPlayerAutoPlay = 'player_auto_play';
  static const _kPlayerContinueLast = 'player_continue_last';
  static const _kPlayerBackground = 'player_background';
  static const _kPlayerPipAuto = 'player_pip_auto';
  static const _kHardwareDecode = 'player_hardware_decode';
  static const _kSearchHistoryLimit = 'search_history_limit';
  static const _kShowAdEntry = 'show_ad_entry';
  static const _kPlayerSeekStep = 'player_seek_step';

  /// 跳转按钮的秒数下限.
  static const playerSeekStepMin = 80.0;

  /// 跳转按钮的秒数上限.
  static const playerSeekStepMax = 100.0;

  /// 跳转按钮的默认秒数, 用于跳过片头片尾.
  static const playerSeekStepDefault = 90.0;

  static int get _themeMode =>
      GStorage.setting.get(_kThemeMode, defaultValue: 0) as int;
  static set _themeMode(int value) => GStorage.setting.put(_kThemeMode, value);

  /// 主题模式, 0 跟随系统, 1 浅色, 2 深色.
  static int get themeMode => _themeMode;
  static set themeMode(int value) => _themeMode = value;

  /// 主题种子色, 为空表示使用默认色.
  static int? get themeColor => GStorage.setting.get(_kThemeColor) as int?;
  static set themeColor(int? value) {
    if (value == null) {
      GStorage.setting.delete(_kThemeColor);
    } else {
      GStorage.setting.put(_kThemeColor, value);
    }
  }

  /// 是否使用系统取色.
  static bool get dynamicColor =>
      GStorage.setting.get(_kDynamicColor, defaultValue: true) as bool;
  static set dynamicColor(bool value) =>
      GStorage.setting.put(_kDynamicColor, value);

  static bool get danmakuEnable => DanmakuPreferencesStore.read().enabled;
  static set danmakuEnable(bool value) =>
      DanmakuPreferencesStore.updateLegacy((p) => p.copyWith(enabled: value));

  static double get danmakuOpacity => DanmakuPreferencesStore.read().opacity;
  static set danmakuOpacity(double value) =>
      DanmakuPreferencesStore.updateLegacy((p) => p.copyWith(opacity: value));

  static double get danmakuFontSize => DanmakuPreferencesStore.read().fontSize;
  static set danmakuFontSize(double value) =>
      DanmakuPreferencesStore.updateLegacy((p) => p.copyWith(fontSize: value));

  static double get danmakuArea => DanmakuPreferencesStore.read().area;
  static set danmakuArea(double value) =>
      DanmakuPreferencesStore.updateLegacy((p) => p.copyWith(area: value));

  static double get danmakuSpeed => DanmakuPreferencesStore.read().duration;
  static set danmakuSpeed(double value) =>
      DanmakuPreferencesStore.updateLegacy((p) => p.copyWith(duration: value));

  static double get danmakuStroke => DanmakuPreferencesStore.read().strokeWidth;
  static set danmakuStroke(double value) =>
      DanmakuPreferencesStore.updateLegacy(
        (p) => p.copyWith(strokeWidth: value),
      );

  static bool get danmakuHideScroll =>
      DanmakuPreferencesStore.read().hideScroll;
  static set danmakuHideScroll(bool value) =>
      DanmakuPreferencesStore.updateLegacy(
        (p) => p.copyWith(hideScroll: value),
      );

  static bool get danmakuHideTop => DanmakuPreferencesStore.read().hideTop;
  static set danmakuHideTop(bool value) =>
      DanmakuPreferencesStore.updateLegacy((p) => p.copyWith(hideTop: value));

  static bool get danmakuHideBottom =>
      DanmakuPreferencesStore.read().hideBottom;
  static set danmakuHideBottom(bool value) =>
      DanmakuPreferencesStore.updateLegacy(
        (p) => p.copyWith(hideBottom: value),
      );

  /// 默认播放倍速.
  static double get playerSpeed =>
      GStorage.setting.get(_kPlayerSpeed, defaultValue: 1.0) as double;
  static set playerSpeed(double value) =>
      GStorage.setting.put(_kPlayerSpeed, value);

  /// 播放音量, 0-100, 跨视频沿用.
  static double get playerVolume =>
      GStorage.setting.get(_kPlayerVolume, defaultValue: 100.0) as double;
  static set playerVolume(double value) =>
      GStorage.setting.put(_kPlayerVolume, value);

  static bool get playerAutoPlay =>
      GStorage.setting.get(_kPlayerAutoPlay, defaultValue: true) as bool;
  static set playerAutoPlay(bool value) =>
      GStorage.setting.put(_kPlayerAutoPlay, value);

  /// 进入播放页是否续播上次进度.
  static bool get playerContinueLast =>
      GStorage.setting.get(_kPlayerContinueLast, defaultValue: true) as bool;
  static set playerContinueLast(bool value) =>
      GStorage.setting.put(_kPlayerContinueLast, value);

  /// 是否允许后台继续播放音频.
  static bool get playerBackground =>
      GStorage.setting.get(_kPlayerBackground, defaultValue: true) as bool;
  static set playerBackground(bool value) =>
      GStorage.setting.put(_kPlayerBackground, value);

  /// 回到桌面或切到其他应用时是否自动进入画中画.
  static bool get playerPipAuto =>
      GStorage.setting.get(_kPlayerPipAuto, defaultValue: true) as bool;
  static set playerPipAuto(bool value) =>
      GStorage.setting.put(_kPlayerPipAuto, value);

  static bool get hardwareDecode =>
      GStorage.setting.get(_kHardwareDecode, defaultValue: true) as bool;
  static set hardwareDecode(bool value) =>
      GStorage.setting.put(_kHardwareDecode, value);

  static int get searchHistoryLimit =>
      GStorage.setting.get(_kSearchHistoryLimit, defaultValue: 20) as int;
  static set searchHistoryLimit(int value) =>
      GStorage.setting.put(_kSearchHistoryLimit, value);

  /// 是否在首页显示广告入口.
  static bool get showAdEntry =>
      GStorage.setting.get(_kShowAdEntry, defaultValue: true) as bool;
  static set showAdEntry(bool value) =>
      GStorage.setting.put(_kShowAdEntry, value);

  /// 播放器跳转按钮一次前进的秒数.
  ///
  /// 旧版本或手工写入的值先收敛到 0.1 秒精度与允许区间, 再交给界面使用.
  static double get playerSeekStep {
    final raw = GStorage.setting.get(_kPlayerSeekStep);
    return normalizeSeekStep(
      raw is num ? raw.toDouble() : playerSeekStepDefault,
    );
  }

  static set playerSeekStep(double value) =>
      GStorage.setting.put(_kPlayerSeekStep, normalizeSeekStep(value));

  /// 收敛跳转秒数, 非法值回落到默认值.
  static double normalizeSeekStep(double value) {
    if (!value.isFinite) {
      return playerSeekStepDefault;
    }
    final clamped = value.clamp(playerSeekStepMin, playerSeekStepMax);
    return (clamped * 10).roundToDouble() / 10;
  }

  /// 请求使用的站点地址.
  static String get baseUrl => Constants.baseUrl;
}
