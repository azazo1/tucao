import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tucao/common/adaptive.dart';
import 'package:tucao/common/style.dart';
import 'package:tucao/common/widgets/loading_widget.dart';
import 'package:tucao/common/widgets/video_card.dart';
import 'package:tucao/http/week_http.dart';
import 'package:tucao/models/site_favorite.dart';
import 'package:tucao/models/video.dart';
import 'package:tucao/models/week_update_time.dart';
import 'package:tucao/pages/home/week_controller.dart';
import 'package:tucao/pages/home/week_order.dart';
import 'package:tucao/pages/home/widgets/continue_watching_banner.dart';
import 'package:tucao/services/account_service.dart';
import 'package:tucao/services/block_service.dart';
import 'package:tucao/services/home_display_service.dart';
import 'package:tucao/services/site_favorite_service.dart';
import 'package:tucao/services/site_notice_service.dart';
import 'package:tucao/services/week_update_time_service.dart';

/// 新番时间表.
///
/// 站点把周日到周六以及剧场, 天朝共九组数据一次性渲染在首页,
/// 这里按同一顺序做成分组切换的网格.
class WeekView extends StatefulWidget {
  const WeekView({super.key});

  @override
  State<WeekView> createState() => _WeekViewState();
}

class _WeekViewState extends State<WeekView>
    with AutomaticKeepAliveClientMixin {
  late final String _tag = 'week_${identityHashCode(this)}';

  late final WeekController _controller = Get.put(WeekController(), tag: _tag);

  /// 上一次请求更新时刻的列表签名.
  ///
  /// 时刻要逐部请求播放页, 只在分组或列表内容变化时才重新发, 重建不算.
  String? _timesSignature;

  /// 新的时刻请求已经定下, 但要等这一帧画完才发出.
  ///
  /// 以前请求失败的番还留在已有结果里, 要等请求发出才会被重新计为等待中,
  /// 这期间不能判定本组已经到齐.
  bool _requesting = false;

  /// 到齐前的展示顺序.
  final _order = WeekOrderGate();

  /// 等时刻到齐的上限, 超时后先按已有数据排一次.
  static const _settleTimeout = Duration(seconds: 3);

  Timer? _settleTimer;

  /// 已经处理过到齐计时的分组, 同一组只计时一次.
  String? _settleGroup;

  @override
  bool get wantKeepAlive => true;

  /// 站点追番整份缓存, 只在登录后拉取, 没登录时拉只会失败并进入冷却.
  SiteFavoriteService? get _favorites {
    if (!Get.isRegistered<AccountService>() ||
        !AccountService.instance.isLogin) {
      return null;
    }
    return SiteFavoriteService.instance;
  }

  @override
  void initState() {
    super.initState();
    final favorites = _favorites;
    if (favorites != null) {
      unawaited(favorites.ensureLoaded());
    }
  }

  @override
  void dispose() {
    _settleTimer?.cancel();
    if (Get.isRegistered<WeekController>(tag: _tag)) {
      Get.delete<WeekController>(tag: _tag);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final display = Get.isRegistered<HomeDisplayService>()
        ? HomeDisplayService.instance
        : null;
    final schedule = Get.isRegistered<WeekUpdateTimeService>()
        ? WeekUpdateTimeService.instance
        : null;
    return Obx(() {
      // 排序开关变化时重排; 时刻数据由 `times` 这个 RxMap 自己触发订阅.
      final sortByTime = display?.weekSortByUpdateTime.value ?? true;
      if (_controller.firstLoading.value) {
        return const LoadingWidget();
      }
      final error = _controller.error.value;
      if (error != null) {
        return ErrorWidgetView(message: error, onRetry: _controller.load);
      }
      final groups = _controller.groups;
      if (groups.isEmpty) {
        // 分组为空时不能走 clamp, Dart 的 clamp 要求下界不大于上界.
        return const EmptyWidget(message: '时间表暂时没有内容');
      }
      final index = _controller.index.value.clamp(0, groups.length - 1);
      final current = groups[index];
      final todayIndex = WeekController.todayIndex(groups.length);
      final visible = current.list.withoutBlocked();
      // 先定下请求, 下面判断是否到齐时要用到 `_requesting`.
      _requestTimes(schedule, current.title, visible);
      final favorites = _favorites;
      final followed = {
        for (final item in favorites?.list ?? const <SiteFavoriteItem>[])
          item.hid,
      };
      final arranged = arrangeWeekItems(
        visible,
        followed: followed,
        times: schedule?.times ?? const <String, WeekUpdateTime>{},
        sortByTime: sortByTime,
      );
      final settledCount = schedule == null
          ? visible.length
          : visible.where((e) => schedule.settled.contains(e.hid)).length;
      final timesReady =
          schedule == null ||
          (!_requesting && settledCount == visible.length);
      // 追番列表晚到也会把已追的番挪到前面, 一并等它.
      final favoritesReady = favorites == null || !favorites.loading.value;
      final ready = favoritesReady && (!sortByTime || timesReady);
      // 排序开关也算进分组键, 切换开关时重新开始等待, 不沿用上次的到齐状态.
      final orderKey = '${current.title}|$sortByTime';
      final items = _order.resolve(
        group: orderKey,
        arranged: arranged,
        ready: ready,
      );
      _watchSettle(orderKey, ready);
      // 逐条读一次时刻: 既订阅 `times` 的后续变化, 也把本轮要显示的内容
      // 定下来. 关掉排序时 arrangeWeekItems 不会碰时刻, 这里仍然要读.
      final times = <String, WeekUpdateTime>{};
      for (final item in items) {
        final time = schedule?.times[item.hid];
        if (time != null) {
          times[item.hid] = time;
        }
      }
      // 只有还会再重排时才显示进度, 关掉排序时时刻只补角标, 不必提示.
      final progress = sortByTime && !timesReady && visible.isNotEmpty
          ? settledCount / visible.length
          : null;

      return Column(
        children: [
          // 横屏矮屏时继续观看并进首页顶部的一行横幅, 这里不再重复显示.
          if (!Adaptive.useSideTabs(context)) const ContinueWatchingBanner(),
          _WeekTabBar(
            groups: groups,
            index: index,
            todayIndex: todayIndex,
            onChanged: _controller.changeIndex,
          ),
          _SettleProgress(value: progress),
          Expanded(
            child: AdaptiveBody(
              maxWidth: Adaptive.gridMaxWidth,
              child: LayoutBuilder(
                builder: (context, constraints) => RefreshIndicator(
                  onRefresh: () {
                    if (Get.isRegistered<SiteNoticeService>()) {
                      unawaited(SiteNoticeService.instance.load());
                    }
                    return _controller.refreshList();
                  },
                  child: items.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: const [
                            SizedBox(height: 120),
                            EmptyWidget(message: '这一天还没有更新'),
                          ],
                        )
                      : _WeekGrid(
                          items: items,
                          followed: followed,
                          times: times,
                          width: constraints.maxWidth,
                          isToday: index == todayIndex,
                        ),
                ),
              ),
            ),
          ),
        ],
      );
    });
  }

  /// 为当前分组里的番剧取更新时刻.
  ///
  /// 签名按站点原顺序算, 卡片重排不会让它变化. 签名没变时不再重复排队,
  /// 播放页请求一次就够.
  void _requestTimes(
    WeekUpdateTimeService? schedule,
    String groupTitle,
    List<VideoModel> items,
  ) {
    if (schedule == null) {
      return;
    }
    final signature = '$groupTitle|${items.map((e) => e.hid).join(',')}';
    if (_timesSignature == signature) {
      return;
    }
    _timesSignature = signature;
    _requesting = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      schedule.ensure(items.map((e) => e.hid));
      // 本组全是已有时刻的番时 ensure 不会改动任何 Rx, 这里自己触发重建.
      setState(() => _requesting = false);
    });
  }

  /// 本组没到齐时开始计时, 超时先按已有数据排一次.
  ///
  /// 同一组只计时一次, 兜底之后就等全部到齐再排最后一次.
  void _watchSettle(String group, bool ready) {
    if (ready) {
      _settleTimer?.cancel();
      _settleTimer = null;
      _settleGroup = group;
      return;
    }
    if (_settleGroup == group) {
      return;
    }
    _settleGroup = group;
    _settleTimer?.cancel();
    _settleTimer = Timer(_settleTimeout, () {
      _settleTimer = null;
      if (!mounted) {
        return;
      }
      setState(() => _order.flush(group));
    });
  }
}

/// 分组切换条: 选中的用边框与主色标出, 当天另加一个小圆点.
class _WeekTabBar extends StatelessWidget {
  const _WeekTabBar({
    required this.groups,
    required this.index,
    required this.todayIndex,
    required this.onChanged,
  });

  final List<WeekGroup> groups;
  final int index;

  /// 当天对应的分组下标, 与是否存在对应分组无关, 由调用方算出.
  final int todayIndex;

  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: groups.length,
        separatorBuilder: (context, i) => const SizedBox(width: 6),
        itemBuilder: (context, i) {
          final selected = i == index;
          final today = i == todayIndex;
          return Center(
            child: InkWell(
              onTap: () => onChanged(i),
              borderRadius: BorderRadius.circular(999),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: selected ? scheme.primary : scheme.outlineVariant,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      groups[i].title,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.normal,
                        color: selected ? scheme.primary : null,
                      ),
                    ),
                    if (today) ...[
                      const SizedBox(width: 4),
                      Container(
                        width: 4,
                        height: 4,
                        decoration: BoxDecoration(
                          color: scheme.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 时间表的卡片网格, 重排时卡片平滑移到新位置.
///
/// GridView 没有位置动画, 时刻陆续到达引起的重排会让卡片瞬间跳位.
/// 这里按网格算出每张卡片的坐标, 用 Stack 加 AnimatedPositioned 做补间;
/// 一个分组最多十几张卡片, 全部构建也不影响滚动.
class _WeekGrid extends StatelessWidget {
  const _WeekGrid({
    required this.items,
    required this.followed,
    required this.times,
    required this.width,
    required this.isToday,
  });

  final List<VideoModel> items;
  final Set<String> followed;
  final Map<String, WeekUpdateTime> times;

  /// 网格容器的宽度, 含水平内边距.
  final double width;

  /// 当前分组是否就是当天, 只有当天才判断更新时刻到没到.
  final bool isToday;

  /// 重排动画时长, 与项目里其他隐式动画接近.
  static const duration = Duration(milliseconds: 280);

  static const topPadding = 10.0;
  static const bottomPadding = 16.0;

  @override
  Widget build(BuildContext context) {
    final columns = Style.gridColumns(width);
    final usable = width - Style.horizontalPadding * 2;
    final itemWidth = (usable - Style.gridSpacing * (columns - 1)) / columns;
    final itemHeight = Style.verticalCardExtent(context, itemWidth);
    final rows = (items.length / columns).ceil();
    final height =
        topPadding +
        rows * itemHeight +
        Style.gridRowSpacing * (rows - 1) +
        bottomPadding;
    // 一次构建里用同一个时间点, 免得同一屏的卡片判断不一致.
    final now = DateTime.now();
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: SizedBox(
        height: height,
        child: Stack(
          children: [
            for (var index = 0; index < items.length; index++)
              AnimatedPositioned(
                // 用视频 id 做 key, 重排后同一张卡片沿用原来的 element,
                // 位置变化才会走补间而不是重新创建.
                key: ValueKey(items[index].hid),
                duration: duration,
                curve: Curves.easeOutCubic,
                left:
                    Style.horizontalPadding +
                    (index % columns) * (itemWidth + Style.gridSpacing),
                top:
                    topPadding +
                    (index ~/ columns) * (itemHeight + Style.gridRowSpacing),
                width: itemWidth,
                height: itemHeight,
                child: _WeekCard(
                  video: items[index],
                  followed: followed.contains(items[index].hid),
                  updateTime: times[items[index].hid],
                  available:
                      isToday &&
                      (times[items[index].hid]?.hasReached(now) ?? false),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 时间表卡片.
///
/// 直接用共享的竖版卡片, 集数状态作为封面角标展示, 更新时刻放在底部
/// 信息行的右端; 当天已经到点的番把时钟换成播放图标, 提示可以看了.
class _WeekCard extends StatelessWidget {
  const _WeekCard({
    required this.video,
    this.followed = false,
    this.updateTime,
    this.available = false,
  });

  final VideoModel video;
  final bool followed;
  final WeekUpdateTime? updateTime;

  /// 当天且更新时刻已到, 用播放图标标出来.
  final bool available;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final time = updateTime;
    return VideoCardVertical(
      video: video,
      badge: video.description.isEmpty ? null : video.description,
      followed: followed,
      // 时间表的列表接口没有弹幕数, 恒为 0, 封面角标不再显示.
      showDanmakuCount: false,
      footerTrailing: time == null
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  available ? Icons.play_circle_fill : Icons.schedule,
                  size: 12,
                  color: available ? scheme.primary : scheme.outline,
                ),
                const SizedBox(width: 2),
                Text(
                  time.label,
                  style: TextStyle(
                    fontSize: 11,
                    color: available ? scheme.primary : scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
    );
  }
}

/// 分组切换条下的细进度条, 表示本组更新时刻取回了多少.
///
/// 高度始终占住, 只做淡入淡出, 出现和消失时下面的网格不会跟着上下移动.
class _SettleProgress extends StatelessWidget {
  const _SettleProgress({required this.value});

  /// 0 到 1 的进度, 为空时隐藏.
  final double? value;

  static const height = 2.0;

  @override
  Widget build(BuildContext context) {
    final current = value;
    return SizedBox(
      height: height,
      child: AnimatedOpacity(
        opacity: current == null ? 0 : 1,
        duration: const Duration(milliseconds: 200),
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: current ?? 1),
          duration: const Duration(milliseconds: 200),
          builder: (context, animated, _) => LinearProgressIndicator(
            value: animated,
            minHeight: height,
            backgroundColor: Colors.transparent,
          ),
        ),
      ),
    );
  }
}
