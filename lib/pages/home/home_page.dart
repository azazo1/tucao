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
import 'package:tucao/pages/home/widgets/continue_watching_banner.dart';
import 'package:tucao/pages/home/widgets/main_tab_rail.dart';
import 'package:tucao/pages/home/widgets/site_notice_bar.dart';
import 'package:tucao/pages/home/widgets/site_online_badge.dart';
import 'package:tucao/pages/home/week_view.dart';
import 'package:tucao/router/routes.dart';
import 'package:tucao/services/ad_service.dart';
import 'package:tucao/services/block_service.dart';
import 'package:tucao/services/history_service.dart';
import 'package:tucao/services/home_display_service.dart';
import 'package:tucao/services/site_notice_service.dart';
import 'package:tucao/services/update_service.dart';

/// 首页.
///
/// 顶部第一个标签是新番时间表, 之后按站点顶级分区分页,
/// 每页内部再用子分区筛选, 内容为两列竖版卡片的网格.
/// 横屏矮屏下标签改到左侧竖排, 站务通知与继续观看并成顶上的一行横幅,
/// 把纵向空间尽量留给内容.
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

  /// 顶栏下半部分: 有没看过的站务文章时, 通知卡片在主标签栏上方.
  ///
  /// 顶栏的 bottom 要求固定高度, 卡片收起时整段高度跟着变,
  /// 所以由 [build] 里的 Obx 在可见性变化时重建.
  PreferredSizeWidget _buildBottom({required bool showNotice}) {
    final tabBar = TabBar(
      controller: _tabController,
      isScrollable: true,
      tabAlignment: TabAlignment.start,
      tabs: [for (final label in _tabLabels) Tab(text: label)],
    );
    if (!showNotice) {
      return tabBar;
    }
    return PreferredSize(
      preferredSize: Size.fromHeight(
        SiteNoticeBar.height + tabBar.preferredSize.height,
      ),
      child: Column(children: [const SiteNoticeBar(), tabBar]),
    );
  }

  /// 主标签名字, 竖排条与横排标签栏共用.
  List<String> get _tabLabels => [
    '时间表',
    for (final channel in ChannelData.list) channel.name,
    '档案',
  ];

  @override
  Widget build(BuildContext context) {
    final side = Adaptive.useSideTabs(context);
    if (!Get.isRegistered<SiteNoticeService>()) {
      return _buildScaffold(showNotice: false, side: side);
    }
    return Obx(
      () => _buildScaffold(showNotice: SiteNoticeBar.visible, side: side),
    );
  }

  Widget _buildScaffold({required bool showNotice, required bool side}) {
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
        bottom: side ? null : _buildBottom(showNotice: showNotice),
      ),
      body: side ? _buildSideLayout() : _buildTabView(),
    );
  }

  Widget _buildTabView() {
    return TabBarView(
      controller: _tabController,
      children: [
        const WeekView(),
        for (final channel in ChannelData.list)
          _ChannelTabView(channel: channel, home: _home),
        const ArticlePage(embedded: true),
      ],
    );
  }

  /// 横屏矮屏下的布局: 顶上一条横幅, 下面是左侧竖排标签与内容.
  Widget _buildSideLayout() {
    return Column(
      children: [
        _buildBannerRow(),
        Expanded(
          child: ListenableBuilder(
            listenable: _tabController,
            builder: (context, child) => Row(
              children: [
                MainTabRail(
                  labels: _tabLabels,
                  index: _tabController.index,
                  onSelected: (index) => _tabController.animateTo(index),
                ),
                const VerticalDivider(width: 0.5),
                Expanded(child: child!),
              ],
            ),
            child: _buildTabView(),
          ),
        ),
      ],
    );
  }

  /// 站务通知与继续观看并排的一行横幅.
  ///
  /// 竖屏时这两块分别挂在顶栏下与时间表页内, 横屏矮屏下并成一行,
  /// 从两块叠起来的一百多 dp 里省出大半. 两边都没有内容时整行不占位.
  Widget _buildBannerRow() {
    return Obx(() {
      final showNotice =
          Get.isRegistered<SiteNoticeService>() && SiteNoticeBar.visible;
      final showContinue = _continueWatchingVisible;
      if (!showNotice && !showContinue) {
        return const SizedBox.shrink();
      }
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
        child: Row(
          children: [
            if (showNotice)
              const Expanded(flex: 3, child: SiteNoticeBar(compact: true)),
            if (showNotice && showContinue) const SizedBox(width: 10),
            if (showContinue)
              const Expanded(
                flex: 2,
                child: ContinueWatchingBanner(compact: true),
              ),
          ],
        ),
      );
    });
  }

  /// 继续观看卡片是否会显示, 决定横幅要不要给它留位置.
  ///
  /// 挑选规则与卡片自身一致, 因此这里为真时右边一定有内容.
  bool get _continueWatchingVisible {
    if (!Get.isRegistered<HistoryService>() ||
        !Get.isRegistered<HomeDisplayService>()) {
      return false;
    }
    if (!HomeDisplayService.instance.showContinueWatching.value) {
      return false;
    }
    return ContinueWatchingBanner.pickAll(
      HistoryService.instance.list,
      DateTime.now(),
    ).isNotEmpty;
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
    return AdaptiveBody(maxWidth: Adaptive.gridMaxWidth, child: _buildGrid());
  }

  Widget _buildGrid() {
    return LayoutBuilder(
      builder: (context, constraints) => Obx(() {
        final raw = _controller.list;
        final items = raw.withoutBlocked();
        final error = _controller.error.value;
        if (_controller.firstLoading.value) {
          // 用和真实卡片同样排布的骨架占位, 数据到了不会整屏跳一下.
          return VideoGridSkeleton(
            gridDelegate: Style.videoGrid(context, constraints.maxWidth),
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          );
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
