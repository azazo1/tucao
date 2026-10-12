import 'package:canvas_danmaku/canvas_danmaku.dart';

/// 弹幕样式独立版本, 不影响应用其它存储结构.
class DanmakuPreferences {
  const DanmakuPreferences({
    this.enabled = true,
    this.opacity = 1,
    this.fontSize = 16,
    this.fontWeight = 4,
    this.fontFamily,
    this.area = 1,
    this.duration = 8,
    this.staticDuration = 5,
    this.strokeWidth = 1.5,
    this.lineHeight = 1.6,
    this.safeArea = true,
    this.hideScroll = false,
    this.hideTop = false,
    this.hideBottom = false,
    this.massiveMode = false,
  });

  static const version = 1;
  static const defaults = DanmakuPreferences();
  final bool enabled;
  final double opacity;
  final double fontSize;
  final int fontWeight;
  final String? fontFamily;
  final double area;
  final double duration;
  final double staticDuration;
  final double strokeWidth;
  final double lineHeight;
  final bool safeArea;
  final bool hideScroll;
  final bool hideTop;
  final bool hideBottom;
  final bool massiveMode;

  static double _number(Object? value, double fallback, double min, double max) {
    if (value is! num || !value.isFinite) return fallback;
    return value.toDouble().clamp(min, max).toDouble();
  }

  static bool _flag(Object? value, bool fallback) =>
      value is bool ? value : fallback;

  factory DanmakuPreferences.fromMap(Map map) {
    final weight = map['fontWeight'];
    return DanmakuPreferences(
      enabled: _flag(map['enabled'], true),
      opacity: _number(map['opacity'], 1, 0, 1),
      fontSize: _number(map['fontSize'], 16, 8, 40),
      fontWeight: weight is int ? weight.clamp(0, 8).toInt() : 4,
      fontFamily: map['fontFamily'] == 'sans-serif' ? 'sans-serif' : null,
      area: _number(map['area'], 1, 0.1, 1),
      duration: _number(map['duration'], 8, 1, 30),
      staticDuration: _number(map['staticDuration'], 5, 1, 30),
      strokeWidth: _number(map['strokeWidth'], 1.5, 0, 5),
      lineHeight: _number(map['lineHeight'], 1.6, 1, 3),
      safeArea: _flag(map['safeArea'], true),
      hideScroll: _flag(map['hideScroll'], false),
      hideTop: _flag(map['hideTop'], false),
      hideBottom: _flag(map['hideBottom'], false),
      massiveMode: _flag(map['massiveMode'], false),
    );
  }

  Map<String, Object?> toMap() => {
    'version': version,
    'enabled': enabled,
    'opacity': opacity,
    'fontSize': fontSize,
    'fontWeight': fontWeight,
    'fontFamily': fontFamily,
    'area': area,
    'duration': duration,
    'staticDuration': staticDuration,
    'strokeWidth': strokeWidth,
    'lineHeight': lineHeight,
    'safeArea': safeArea,
    'hideScroll': hideScroll,
    'hideTop': hideTop,
    'hideBottom': hideBottom,
    'massiveMode': massiveMode,
  };

  DanmakuPreferences get normalized => DanmakuPreferences.fromMap(toMap());

  DanmakuPreferences copyWith({
    bool? enabled, double? opacity, double? fontSize, int? fontWeight,
    String? fontFamily, bool clearFontFamily = false, double? area,
    double? duration, double? staticDuration, double? strokeWidth,
    double? lineHeight, bool? safeArea, bool? hideScroll, bool? hideTop,
    bool? hideBottom, bool? massiveMode,
  }) => DanmakuPreferences(
    enabled: enabled ?? this.enabled,
    opacity: opacity ?? this.opacity,
    fontSize: fontSize ?? this.fontSize,
    fontWeight: fontWeight ?? this.fontWeight,
    fontFamily: clearFontFamily ? null : fontFamily ?? this.fontFamily,
    area: area ?? this.area,
    duration: duration ?? this.duration,
    staticDuration: staticDuration ?? this.staticDuration,
    strokeWidth: strokeWidth ?? this.strokeWidth,
    lineHeight: lineHeight ?? this.lineHeight,
    safeArea: safeArea ?? this.safeArea,
    hideScroll: hideScroll ?? this.hideScroll,
    hideTop: hideTop ?? this.hideTop,
    hideBottom: hideBottom ?? this.hideBottom,
    massiveMode: massiveMode ?? this.massiveMode,
  ).normalized;

  DanmakuOption toOption() {
    final value = normalized;
    return DanmakuOption(
      opacity: value.enabled ? value.opacity : 0,
      fontSize: value.fontSize,
      fontWeight: value.fontWeight,
      fontFamily: value.fontFamily,
      area: value.area,
      duration: value.duration,
      staticDuration: value.staticDuration,
      strokeWidth: value.strokeWidth,
      lineHeight: value.lineHeight,
      safeArea: value.safeArea,
      hideScroll: value.hideScroll,
      hideTop: value.hideTop,
      hideBottom: value.hideBottom,
      massiveMode: value.massiveMode,
    );
  }
}
