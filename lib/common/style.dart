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

  /// 两列网格里竖版卡片的固定高度.
  ///
  /// 卡片是封面加下方内容区, 内容区含标题两行, 统计行与作者行,
  /// 因此这里按字号估算, 并跟随系统字体缩放. 常数项是内容区的内边距
  /// 与三行之间的间距.
  static double verticalCardExtent(
    BuildContext context,
    double itemWidth,
  ) {
    final theme = Theme.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    final titleSize = theme.textTheme.bodyMedium?.fontSize ?? 14;
    final labelSize = theme.textTheme.labelSmall?.fontSize ?? 11;
    final contentHeight =
        scaler.scale(titleSize) * 1.35 * 2 +
        scaler.scale(labelSize) * 1.45 * 2 +
        26;
    return itemWidth / coverAspectRatio + contentHeight;
  }

  /// 网格水平内边距, 与页面其他部分的留白一致.
  static const horizontalPadding = 12.0;

  /// 网格内卡片之间的间距.
  static const gridSpacing = 10.0;

  /// 网格内卡片的最小宽度, 再窄标题就会挤成两三个字.
  static const minCardWidth = 165.0;

  /// 网格列数上限, 防止超宽屏下卡片被拉得过大.
  static const maxGridColumns = 6;

  /// 竖版卡片网格的列数.
  ///
  /// 按卡片最小宽度均分可用宽度: 手机竖屏两列, 横屏与平板随宽度增加列数.
  static int gridColumns(double availableWidth) {
    final usable = availableWidth - horizontalPadding * 2;
    if (usable <= 0) {
      return 2;
    }
    final columns =
        ((usable + gridSpacing) / (minCardWidth + gridSpacing)).floor();
    return columns.clamp(2, maxGridColumns).toInt();
  }

  /// 竖版卡片的网格代理, 列数与卡片高度都跟随可用宽度.
  ///
  /// [availableWidth] 是网格容器自身的宽度, 水平内边距从这里扣除.
  static SliverGridDelegate videoGrid(
    BuildContext context,
    double availableWidth,
  ) {
    final columns = gridColumns(availableWidth);
    final usable = availableWidth - horizontalPadding * 2;
    final itemWidth = (usable - gridSpacing * (columns - 1)) / columns;
    return SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: columns,
      crossAxisSpacing: gridSpacing,
      mainAxisSpacing: 12,
      mainAxisExtent: verticalCardExtent(context, itemWidth),
    );
  }

  /// 用户横幅的回退底色.
  ///
  /// 没有横幅, 横幅加载失败, 或者横幅本身就是一张近乎全黑的图时, 页头改用
  /// 主题容器色拼一层渐变, 免得整块糊成黑色.
  static LinearGradient bannerGradient(ColorScheme scheme) {
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        scheme.primaryContainer.withValues(alpha: 0.9),
        scheme.secondaryContainer.withValues(alpha: 0.9),
      ],
    );
  }

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
      // InkSparkle 会用到运行时片元着色器, Adreno 的 Vulkan 驱动在编译
      // 这类着色器时偶发空指针崩溃, 这里改用普通水波纹规避.
      splashFactory: InkRipple.splashFactory,
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
      // 卡片底色取容器色的高一档, 再描一圈轮廓.
      //
      // 暗色下 surface 与 surfaceContainerLow 的亮度差几乎看不出来, 卡片和
      // 页面背景糊成一片, 描边能给出确定的边界, 底色高两档则拉开层次.
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerHigh,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cardRadius),
          side: BorderSide(color: scheme.outlineVariant),
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
