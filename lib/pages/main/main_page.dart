import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tucao/common/adaptive.dart';
import 'package:tucao/common/widgets/reselect_scroll.dart';
import 'package:tucao/pages/home/home_page.dart';
import 'package:tucao/pages/mine/mine_page.dart';
import 'package:tucao/pages/rank/rank_page.dart';
import 'package:tucao/services/message_count_service.dart';
import 'package:tucao/utils/logger.dart';

/// 应用主框架.
///
/// 三个常驻页面保持状态, 切换时不重建. 搜索从首页右上角进入, 不占底部 tab.
/// 手机竖屏用底部导航, 横屏与平板改用左侧导航栏, 让内容区拿到更多宽度.
class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage>
    with SingleTickerProviderStateMixin {
  int _index = 0;

  /// 切换入口时新页面淡入并微微上移, 不再生硬地闪一下.
  ///
  /// 初始停在终点, 冷启动的第一页不做动画.
  late final _switchAnimation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
    value: 1,
  );
  late final _fade = CurvedAnimation(
    parent: _switchAnimation,
    curve: Curves.easeOut,
  );
  late final _slide = Tween(
    begin: const Offset(0, 0.02),
    end: Offset.zero,
  ).animate(_fade);

  /// 旋转屏幕时主框架在底部导航与侧边导航之间切换,
  /// 页面栈用同一个 key 搬到新位置, 保留各页的滚动与分页状态.
  final _pagesKey = GlobalKey();

  static const _pages = [HomePage(), RankPage(embedded: true), MinePage()];

  /// 图标, 选中图标与标签.
  static const _items = [
    (Icons.home_outlined, Icons.home, '首页'),
    (Icons.leaderboard_outlined, Icons.leaderboard, '排行'),
    (Icons.person_outline, Icons.person, '我的'),
  ];

  /// 「我的」在入口列表里的位置, 未读角标挂在它上面.
  static const _mineIndex = 2;

  @override
  void initState() {
    super.initState();
    // 未读数不必等用户点开「我的」, 入口上的角标一开始就要显示.
    unawaited(MessageCountService.instance.reload(auto: true));
  }

  /// 入口图标, 「我的」上面叠一个未读数字.
  ///
  /// 数字会随未读数变化, 因此单独用 Obx 包住图标, 切换 tab 时不牵动整条导航.
  Widget _entryIcon(int index, IconData icon) {
    if (index != _mineIndex) {
      return Icon(icon);
    }
    return Obx(() {
      final count = MessageCountService.instance.total;
      return Badge(
        label: Text('$count'),
        isLabelVisible: count > 0,
        child: Icon(icon),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final wide = Adaptive.isWide(context);
    return PopScope(
      canPop: _index == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _index != 0) {
          _switchTo(0);
        }
      },
      child: Scaffold(
        body: wide
            ? Row(
                children: [
                  NavigationRail(
                    selectedIndex: _index,
                    onDestinationSelected: _select,
                    labelType: NavigationRailLabelType.all,
                    destinations: [
                      for (final (index, item) in _items.indexed)
                        NavigationRailDestination(
                          icon: _entryIcon(index, item.$1),
                          selectedIcon: _entryIcon(index, item.$2),
                          label: Text(item.$3),
                        ),
                    ],
                  ),
                  const VerticalDivider(width: 0.5),
                  Expanded(child: _buildPages()),
                ],
              )
            : _buildPages(),
        bottomNavigationBar: wide
            ? null
            : NavigationBar(
                selectedIndex: _index,
                onDestinationSelected: _select,
                destinations: [
                  for (final (index, item) in _items.indexed)
                    NavigationDestination(
                      icon: _entryIcon(index, item.$1),
                      selectedIcon: _entryIcon(index, item.$2),
                      label: item.$3,
                    ),
                ],
              ),
      ),
    );
  }

  /// 每个常驻页面的 key, 重复点击时只在当前页里找列表.
  final _pageKeys = [for (final _ in _pages) GlobalKey()];

  void _select(int value) {
    if (value == _index) {
      _reselect();
      return;
    }
    _switchTo(value);
  }

  void _switchTo(int value) {
    setState(() => _index = value);
    // 系统关闭了动画时直接切换.
    if (MediaQuery.disableAnimationsOf(context)) {
      _switchAnimation.value = 1;
      return;
    }
    _switchAnimation.forward(from: 0);
  }

  @override
  void dispose() {
    _fade.dispose();
    _switchAnimation.dispose();
    super.dispose();
  }

  /// 重复点击当前入口: 先回顶部, 已在顶部时下拉刷新.
  void _reselect() {
    final context = _pageKeys[_index].currentContext;
    if (context == null) return;
    final action = ReselectScroll.handle(context);
    Log.d('重复点击 ${_items[_index].$3}: ${action.name}');
  }

  /// 页面栈仍是 IndexedStack, 各页常驻保留状态, 动画只作用在最外层.
  Widget _buildPages() {
    return FadeTransition(
      key: _pagesKey,
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: IndexedStack(
          index: _index,
          children: [
            for (final (index, page) in _pages.indexed)
              KeyedSubtree(key: _pageKeys[index], child: page),
          ],
        ),
      ),
    );
  }
}
