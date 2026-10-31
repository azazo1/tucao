import 'package:flutter/material.dart';

/// 横屏与平板适配用的断点与容器.
///
/// 断点主要看宽度: 手机竖屏按单栏排布, 手机横屏与平板按宽度增加内容密度.
/// 高度只在横屏矮屏这一种情形参与判断: 这种屏幕上纵向空间比宽度更紧,
/// 需要把顶上的横排标签竖到一边. 竖屏不看高度, 免得软键盘弹出时布局来回跳.
abstract final class Adaptive {
  /// 手机竖屏的上界, 也是宽屏主框架的起点.
  static const compactWidth = 600.0;

  /// 平板横屏与竖屏的分界, 左右分栏页面从这里开始.
  static const expandedWidth = 840.0;

  /// 手机横屏也算宽屏, 播放页从这一宽度开始左右分栏.
  ///
  /// 640 宽时右侧内容列约 250, 仍能正常显示简介与评论.
  static const splitWidth = 640.0;

  /// 文字为主页面的最大内容宽度, 避免一行文字过长.
  static const contentMaxWidth = 760.0;

  /// 横版视频列表的最大内容宽度.
  static const listMaxWidth = 1080.0;

  /// 登录, 注册一类表单的最大宽度.
  static const formMaxWidth = 520.0;

  /// 竖版卡片网格的最大内容宽度.
  static const gridMaxWidth = 1200.0;

  /// 横屏手机的内容区高度上限, 低于它就算矮屏.
  ///
  /// 手机横屏常见 360~430 高, 顶栏与首页横幅放完就只剩一截内容区.
  static const shortHeight = 480.0;

  static double widthOf(BuildContext context) =>
      MediaQuery.sizeOf(context).width;

  static Size sizeOf(BuildContext context) => MediaQuery.sizeOf(context);

  static bool isWide(BuildContext context) => widthOf(context) >= compactWidth;

  /// 播放页是否左右分栏.
  ///
  /// 横屏手机与平板横屏都分栏, 平板竖屏内容列更宽, 也分栏;
  /// 手机竖屏保持上下结构.
  static bool useSplitVideoLayout(BuildContext context) =>
      splitVideoLayout(sizeOf(context));

  /// [useSplitVideoLayout] 的纯函数版本, 便于单独验证.
  static bool splitVideoLayout(Size size) {
    return (size.width > size.height && size.width >= splitWidth) ||
        size.width >= expandedWidth;
  }

  /// 首页主标签是否放到左侧竖排.
  ///
  /// 只在横屏矮屏这样做: 顶上一条横向标签加上首页横幅后, 内容区被压到
  /// 一张卡片都放不下, 竖过来能把这几十个 dp 还给内容.
  static bool useSideTabs(BuildContext context) => sideTabs(sizeOf(context));

  /// [useSideTabs] 的纯函数版本, 便于单独验证.
  ///
  /// 宽度不够时主框架还是底部导航, 撑不出侧栏, 因此一并要求宽屏.
  static bool sideTabs(Size size) =>
      size.width > size.height &&
      size.height < shortHeight &&
      size.width >= compactWidth;

  /// 宽屏下内容居中所需的水平留白, 窄屏为 0.
  ///
  /// 列表页把它加进 [ListView.padding], 不改变页面结构就能把内容收窄居中.
  static double sidePadding(
    BuildContext context, {
    double maxWidth = contentMaxWidth,
  }) {
    final side = (widthOf(context) - maxWidth) / 2;
    return side > 0 ? side : 0;
  }
}

/// 宽屏下把页面内容限制在 [maxWidth] 内并水平居中.
///
/// 纵向约束原样传递, 因此可以直接包住 [ListView] 或 [CustomScrollView].
class AdaptiveBody extends StatelessWidget {
  const AdaptiveBody({
    super.key,
    required this.child,
    this.maxWidth = Adaptive.contentMaxWidth,
    this.alignment = Alignment.topCenter,
  });

  final Widget child;
  final double maxWidth;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
