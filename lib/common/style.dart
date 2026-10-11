import 'package:flutter/material.dart';

/// 主题与样式.
///
/// 站点主色取自官网的粉色, 深浅色主题共用同一套种子色.
abstract final class Style {
  /// 站点主色.
  static const seedColor = Color(0xFFE52958);

  /// 视频卡片圆角.
  static const cardRadius = 8.0;

  /// 页面水平内边距.
  static const pagePadding = EdgeInsets.symmetric(horizontal: 12);

  /// 列表项之间的间距.
  static const listSpacing = 10.0;

  /// 封面宽高比, 站点缩略图是 362x233.
  static const coverAspectRatio = 362 / 233;

  static ThemeData light(ColorScheme? dynamicScheme) => _build(
    dynamicScheme ?? ColorScheme.fromSeed(seedColor: seedColor),
  );

  static ThemeData dark(ColorScheme? dynamicScheme) => _build(
    dynamicScheme ??
        ColorScheme.fromSeed(
          seedColor: seedColor,
          brightness: Brightness.dark,
        ),
  );

  static ThemeData _build(ColorScheme scheme) {
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        scrolledUnderElevation: 0,
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.secondaryContainer,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
      tabBarTheme: TabBarThemeData(
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: Colors.transparent,
        labelColor: scheme.primary,
        unselectedLabelColor: scheme.onSurfaceVariant,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerLow,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cardRadius),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        minVerticalPadding: 10,
        visualDensity: VisualDensity.compact,
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.5),
        thickness: 0.5,
        space: 0.5,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 10,
        ),
        isDense: true,
      ),
    );
  }
}
