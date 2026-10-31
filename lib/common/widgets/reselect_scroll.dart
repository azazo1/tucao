import 'dart:async';

import 'package:flutter/material.dart';

/// 重复点击当前导航项时做的事.
enum ReselectAction { scrolledToTop, refreshed, none }

/// 重复点击当前导航项: 不在顶部就滚回顶部, 已经在顶部就触发下拉刷新.
///
/// 各页面的列表没有统一的滚动控制器, 这里直接在页面子树里找可见的竖向列表和
/// [RefreshIndicator]. 保活但不在屏幕上的标签页 (例如首页其他分区) 会被跳过,
/// 免得一次点击把所有分区都刷新一遍.
abstract final class ReselectScroll {
  static const _duration = Duration(milliseconds: 350);

  /// 离顶部超过这么多屏时先跳到第一屏再动画, 长列表不必滚很久.
  static const _jumpScreens = 3;

  static ReselectAction handle(BuildContext root) {
    final screen = Offset.zero & MediaQuery.sizeOf(root);
    final scrollables = <ScrollPosition>[];
    final refreshers = <RefreshIndicatorState>[];

    void visit(Element element) {
      if (element is StatefulElement) {
        final state = element.state;
        if (state is ScrollableState) {
          final position = state.position;
          if (position.hasPixels &&
              position.axis == Axis.vertical &&
              _visible(element, screen)) {
            scrollables.add(position);
          }
        } else if (state is RefreshIndicatorState &&
            _visible(element, screen)) {
          refreshers.add(state);
        }
      }
      element.visitChildren(visit);
    }

    root.visitChildElements(visit);

    final away = scrollables
        .where((p) => p.pixels > p.minScrollExtent + 0.5)
        .toList();
    if (away.isNotEmpty) {
      for (final position in away) {
        final top = position.minScrollExtent;
        final far = position.viewportDimension * _jumpScreens;
        if (position.pixels - top > far) {
          position.jumpTo(top + position.viewportDimension);
        }
        unawaited(
          position.animateTo(
            top,
            duration: _duration,
            curve: Curves.easeOutCubic,
          ),
        );
      }
      return ReselectAction.scrolledToTop;
    }
    if (refreshers.isNotEmpty) {
      unawaited(refreshers.first.show());
      return ReselectAction.refreshed;
    }
    return ReselectAction.none;
  }

  /// 是否真的画在屏幕上.
  ///
  /// 保活的离屏子页面会被列表给一个全零的变换, 变换后的区域面积为零, 这里据此排除.
  static bool _visible(Element element, Rect screen) {
    final box = element.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return false;
    final rect = MatrixUtils.transformRect(
      box.getTransformTo(null),
      Offset.zero & box.size,
    );
    return rect.width > 0 && rect.height > 0 && rect.overlaps(screen);
  }
}
