import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tucao/common/adaptive.dart';
import 'package:tucao/common/style.dart';
import 'package:tucao/common/widgets/channel_bar.dart';
import 'package:tucao/common/widgets/loading_widget.dart';
import 'package:tucao/common/widgets/video_card.dart';
import 'package:tucao/models/channel.dart';
import 'package:tucao/pages/article/article_page.dart';
import 'package:tucao/pages/channel/channel_controller.dart';
import 'package:tucao/pages/home/home_controller.dart';
import 'package:tucao/pages/home/widgets/ad_entry_button.dart';
import 'package:tucao/pages/home/widgets/site_online_badge.dart';
import 'package:tucao/pages/home/week_view.dart';
import 'package:tucao/router/routes.dart';
import 'package:tucao/services/ad_service.dart';
import 'package:tucao/services/block_service.dart';
import 'package:tucao/services/update_service.dart';

/// 首页.
///
/// 顶部第一个标签是新番时间表, 之后按站点顶级分区分页,
/// 每页内部再用子分区筛选, 内容为两列竖版卡片的网格.
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  late final HomeController _home;
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _home = Get.isRegistered<HomeController>()
        ? Get.find<HomeController>()
        : Get.put(HomeController());
    _tabController = TabController(
      length: ChannelData.list.length + 2,
      vsync: this,
    );
    // 首帧之后检查更新, 不与首页的内容请求争抢启动时的网络.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(UpdateService.checkOnStartup(context));
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('吐槽'),
            SizedBox(width: 8),
            Flexible(
              child: Padding(
                padding: EdgeInsets.only(bottom: 6),
                child: SiteOnlineBadge(),
              ),
            ),
          ],
        ),
        titleSpacing: 16,
        actions: [
          Obx(
            () => AdService.instance.enabled.value
                ? const AdEntryButton()
                : const SizedBox.shrink(),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.calendar_month_outlined),
            tooltip: '新番',
            onSelected: (value) {
              switch (value) {
                case 'week':
                  Get.toNamed(Routes.weekBgm);
                case 'index':
                  Get.toNamed(Routes.bgmIndex);
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'week', child: Text('本周新番')),
              PopupMenuItem(value: 'index', child: Text('新番索引')),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: '搜索',
            onPressed: () => Get.toNamed(Routes.search),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [
            const Tab(text: '时间表'),
            for (final channel in ChannelData.list) Tab(text: channel.name),
            const Tab(text: '档案'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          const WeekView(),
          for (final channel in ChannelData.list)
            _ChannelTabView(channel: channel, home: _home),
          const ArticlePage(embedded: true),
        ],
      ),
    );
  }
}

/// 单个顶级分区的页面.
///
/// 子分区切换只改变筛选条件, 各分区的控制器由 [HomeController] 缓存,
/// 因此来回切换不会重新请求.
class _ChannelTabView extends StatefulWidget {
  const _ChannelTabView({required this.channel, required this.home});

  final ChannelModel channel;
  final HomeController home;

  @override
  State<_ChannelTabView> createState() => _ChannelTabViewState();
}

class _ChannelTabViewState extends State<_ChannelTabView>
    with AutomaticKeepAliveClientMixin {
  /// 当前选中的子分区, 为空表示该顶级分区的全部内容.
  ChannelModel? _child;

  late int _tid;
  late ChannelController _controller;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _tid = widget.channel.id;
    _controller = widget.home.of(_tid);
  }

  /// 当前筛选的分区名, 供 "更多" 入口使用.
  String get _name => _child?.name ?? widget.channel.name;

  void _selectChild(int? id) {
    ChannelModel? child;
    for (final item in widget.channel.children) {
      if (item.id == id) {
        child = item;
        break;
      }
    }
    if (id != null && child == null) {
      return;
    }
    if (_child?.id == child?.id) {
      return;
    }
    setState(() {
      _child = child;
      _tid = child?.id ?? widget.channel.id;
      _controller = widget.home.of(_tid);
    });
  }

  void _openChannel() {
    Get.toNamed(Routes.channel, parameters: {'tid': '$_tid', 'name': _name});
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: ChannelBar(
                channels: [
                  for (final child in widget.channel.children)
                    ChannelItem(id: child.id, name: child.name),
                ],
                currentId: _child?.id,
                onChanged: _selectChild,
                showAll: true,
              ),
            ),
            TextButton(
              onPressed: _openChannel,
              style: TextButton.styleFrom(
                minimumSize: Size.zero,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('更多'),
            ),
            const SizedBox(width: 8),
          ],
        ),
        Expanded(child: _buildBody()),
      ],
    );
  }

  Widget _buildBody() {
    return AdaptiveBody(
      maxWidth: Adaptive.gridMaxWidth,
      child: _buildGrid(),
    );
  }

  Widget _buildGrid() {
    return LayoutBuilder(
      builder: (context, constraints) => Obx(() {
        final raw = _controller.list;
        final items = raw.withoutBlocked();
        final error = _controller.error.value;
        if (_controller.firstLoading.value) {
          return const LoadingWidget();
        }
        if (error != null && raw.isEmpty) {
          return ErrorWidgetView(
            message: error,
            onRetry: _controller.loadFirst,
          );
        }
        return RefreshIndicator(
          onRefresh: _controller.refresh,
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (notification.metrics.pixels >=
                  notification.metrics.maxScrollExtent - 300) {
                if (_controller.hasMore && !_controller.loading.value) {
                  _controller.loadMore();
                }
              }
              return false;
            },
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                if (items.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: EmptyWidget(message: '这个分区还没有视频'),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    sliver: SliverGrid(
                      gridDelegate: Style.videoGrid(
                        context,
                        constraints.maxWidth,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, index) =>
                            VideoCardVertical(video: items[index]),
                        childCount: items.length,
                      ),
                    ),
                  ),
                SliverToBoxAdapter(
                  child: LoadMoreFooter(
                    loading: _controller.loading.value,
                    hasMore: _controller.hasMore,
                    onRetry: _controller.loadMore,
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}
