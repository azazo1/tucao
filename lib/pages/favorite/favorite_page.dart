import 'package:flutter/material.dart';
import 'package:tucao/pages/favorite/widgets/local_favorite_list.dart';
import 'package:tucao/pages/favorite/widgets/site_favorite_list.dart';

/// 我的收藏.
///
/// 本地收藏只在这台设备上, 站点追番跟着站点账号走, 两者性质不同,
/// 因此共用一个入口, 在页面里用两个 tab 分开.
class FavoritePage extends StatelessWidget {
  const FavoritePage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('我的收藏'),
          bottom: const TabBar(
            tabs: [Tab(text: '本地收藏'), Tab(text: '追番')],
          ),
        ),
        body: const TabBarView(
          children: [LocalFavoriteList(), SiteFavoriteList()],
        ),
      ),
    );
  }
}
