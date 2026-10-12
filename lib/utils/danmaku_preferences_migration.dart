import 'package:tucao/models/danmaku_preferences.dart';

/// 只读取旧键, 迁移成功后也保留旧数据供回退使用.
abstract final class DanmakuPreferencesMigration {
  static const legacyKeys = <String>[
    'danmaku_enable',
    'danmaku_opacity',
    'danmaku_font_size',
    'danmaku_area',
    'danmaku_speed',
    'danmaku_stroke',
    'danmaku_hide_scroll',
    'danmaku_hide_top',
    'danmaku_hide_bottom',
  ];

  static DanmakuPreferences fromLegacy(Object? Function(String) read) =>
      DanmakuPreferences.fromMap({
        'enabled': read('danmaku_enable'),
        'opacity': read('danmaku_opacity'),
        'fontSize': read('danmaku_font_size'),
        'area': read('danmaku_area'),
        'duration': read('danmaku_speed'),
        'strokeWidth': read('danmaku_stroke'),
        'hideScroll': read('danmaku_hide_scroll'),
        'hideTop': read('danmaku_hide_top'),
        'hideBottom': read('danmaku_hide_bottom'),
      });
}
