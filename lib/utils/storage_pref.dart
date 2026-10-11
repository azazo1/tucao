import 'package:tucao/common/constants.dart';
import 'package:tucao/utils/storage.dart';

/// 用户偏好的读写封装.
///
/// 所有键都带默认值, 首次运行时不会读到空值.
abstract final class Pref {
  static const _kThemeMode = 'theme_mode';
  static const _kThemeColor = 'theme_color';
  static const _kDynamicColor = 'dynamic_color';
  static const _kDanmakuEnable = 'danmaku_enable';
  static const _kDanmakuOpacity = 'danmaku_opacity';
  static const _kDanmakuFontSize = 'danmaku_font_size';
  static const _kDanmakuArea = 'danmaku_area';
  static const _kDanmakuSpeed = 'danmaku_speed';
  static const _kDanmakuStroke = 'danmaku_stroke';
  static const _kDanmakuHideScroll = 'danmaku_hide_scroll';
  static const _kDanmakuHideTop = 'danmaku_hide_top';
  static const _kDanmakuHideBottom = 'danmaku_hide_bottom';
  static const _kPlayerSpeed = 'player_speed';
  static const _kPlayerAutoPlay = 'player_auto_play';
  static const _kPlayerContinueLast = 'player_continue_last';
  static const _kPlayerBackground = 'player_background';
  static const _kHardwareDecode = 'player_hardware_decode';
  static const _kSearchHistoryLimit = 'search_history_limit';

  static int get _themeMode => GStorage.setting.get(_kThemeMode, defaultValue: 0) as int;
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
  static bool get dynamicColor => GStorage.setting.get(_kDynamicColor, defaultValue: true) as bool;
  static set dynamicColor(bool value) => GStorage.setting.put(_kDynamicColor, value);

  static bool get danmakuEnable => GStorage.setting.get(_kDanmakuEnable, defaultValue: true) as bool;
  static set danmakuEnable(bool value) => GStorage.setting.put(_kDanmakuEnable, value);

  static double get danmakuOpacity => GStorage.setting.get(_kDanmakuOpacity, defaultValue: 1.0) as double;
  static set danmakuOpacity(double value) => GStorage.setting.put(_kDanmakuOpacity, value);

  static double get danmakuFontSize => GStorage.setting.get(_kDanmakuFontSize, defaultValue: 16.0) as double;
  static set danmakuFontSize(double value) => GStorage.setting.put(_kDanmakuFontSize, value);

  static double get danmakuArea => GStorage.setting.get(_kDanmakuArea, defaultValue: 1.0) as double;
  static set danmakuArea(double value) => GStorage.setting.put(_kDanmakuArea, value);

  static double get danmakuSpeed => GStorage.setting.get(_kDanmakuSpeed, defaultValue: 8.0) as double;
  static set danmakuSpeed(double value) => GStorage.setting.put(_kDanmakuSpeed, value);

  static double get danmakuStroke => GStorage.setting.get(_kDanmakuStroke, defaultValue: 1.5) as double;
  static set danmakuStroke(double value) => GStorage.setting.put(_kDanmakuStroke, value);

  static bool get danmakuHideScroll => GStorage.setting.get(_kDanmakuHideScroll, defaultValue: false) as bool;
  static set danmakuHideScroll(bool value) => GStorage.setting.put(_kDanmakuHideScroll, value);

  static bool get danmakuHideTop => GStorage.setting.get(_kDanmakuHideTop, defaultValue: false) as bool;
  static set danmakuHideTop(bool value) => GStorage.setting.put(_kDanmakuHideTop, value);

  static bool get danmakuHideBottom => GStorage.setting.get(_kDanmakuHideBottom, defaultValue: false) as bool;
  static set danmakuHideBottom(bool value) => GStorage.setting.put(_kDanmakuHideBottom, value);

  /// 默认播放倍速.
  static double get playerSpeed => GStorage.setting.get(_kPlayerSpeed, defaultValue: 1.0) as double;
  static set playerSpeed(double value) => GStorage.setting.put(_kPlayerSpeed, value);

  static bool get playerAutoPlay => GStorage.setting.get(_kPlayerAutoPlay, defaultValue: true) as bool;
  static set playerAutoPlay(bool value) => GStorage.setting.put(_kPlayerAutoPlay, value);

  /// 进入播放页是否续播上次进度.
  static bool get playerContinueLast =>
      GStorage.setting.get(_kPlayerContinueLast, defaultValue: true) as bool;
  static set playerContinueLast(bool value) => GStorage.setting.put(_kPlayerContinueLast, value);

  /// 是否允许后台继续播放音频.
  static bool get playerBackground =>
      GStorage.setting.get(_kPlayerBackground, defaultValue: true) as bool;
  static set playerBackground(bool value) => GStorage.setting.put(_kPlayerBackground, value);

  static bool get hardwareDecode => GStorage.setting.get(_kHardwareDecode, defaultValue: true) as bool;
  static set hardwareDecode(bool value) => GStorage.setting.put(_kHardwareDecode, value);

  static int get searchHistoryLimit =>
      GStorage.setting.get(_kSearchHistoryLimit, defaultValue: 20) as int;
  static set searchHistoryLimit(int value) => GStorage.setting.put(_kSearchHistoryLimit, value);

  /// 请求使用的站点地址.
  static String get baseUrl => Constants.baseUrl;
}
