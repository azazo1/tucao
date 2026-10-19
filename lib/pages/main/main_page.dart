import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tucao/common/adaptive.dart';
import 'package:tucao/pages/home/home_page.dart';
import 'package:tucao/pages/mine/mine_page.dart';
import 'package:tucao/pages/rank/rank_page.dart';
import 'package:tucao/services/message_count_service.dart';

/// 应用主框架.
///
/// 三个常驻页面保持状态, 切换时不重建. 搜索从首页右上角进入, 不占底部 tab.
/// 手机竖屏用底部导航, 横屏与平板改用左侧导航栏, 让内容区拿到更多宽度.
class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  int _index = 0;

  /// 旋转屏幕时主框架在底部导航与侧边导航之间切换,
  /// 页面栈用同一个 key 搬到新位置, 保留各页的滚动与分页状态.
  final _pagesKey = GlobalKey();

  static const _pages = [
    HomePage(),
    RankPage(embedded: true),
    MinePage(),
  ];

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
          setState(() => _index = 0);
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

  void _select(int value) => setState(() => _index = value);

  Widget _buildPages() {
    return IndexedStack(key: _pagesKey, index: _index, children: _pages);
  }
}
