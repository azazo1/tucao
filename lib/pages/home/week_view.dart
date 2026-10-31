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
      final followed = {
        for (final item in _favorites?.list ?? const <SiteFavoriteItem>[])
          item.hid,
      };
      final items = arrangeWeekItems(
        current.list.withoutBlocked(),
        followed: followed,
        times: schedule?.times ?? const <String, WeekUpdateTime>{},
        sortByTime: sortByTime,
      );
      // 逐条读一次时刻: 既订阅 `times` 的后续变化, 也把本轮要显示的内容
      // 定下来. 关掉排序时 arrangeWeekItems 不会碰时刻, 这里仍然要读.
      final times = <String, WeekUpdateTime>{};
      for (final item in items) {
        final time = schedule?.times[item.hid];
        if (time != null) {
          times[item.hid] = time;
        }
      }
      _requestTimes(schedule, current.title, items);

      return Column(
        children: [
          const ContinueWatchingBanner(),
          _WeekTabBar(
            groups: groups,
            index: index,
            todayIndex: WeekController.todayIndex(groups.length),
            onChanged: _controller.changeIndex,
          ),
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
  /// 列表签名没变时不再重复排队, 播放页请求一次就够.
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      schedule.ensure(items.map((e) => e.hid));
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
  });

  final List<VideoModel> items;
  final Set<String> followed;
  final Map<String, WeekUpdateTime> times;

  /// 网格容器的宽度, 含水平内边距.
  final double width;

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
/// 信息行的右端.
class _WeekCard extends StatelessWidget {
  const _WeekCard({
    required this.video,
    this.followed = false,
    this.updateTime,
  });

  final VideoModel video;
  final bool followed;
  final WeekUpdateTime? updateTime;

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
                Icon(Icons.schedule, size: 12, color: scheme.outline),
                const SizedBox(width: 2),
                Text(
                  time.label,
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
    );
  }
}

/// 已追的番排在前面, 排序开启时两部分内部再按更新时刻升序.
///
/// 时刻要等播放页请求回来才有, 列表会随数据到达整体重排; 没有时刻的
/// 番剧排在所在部分的最后, 彼此之间保持站点原来的顺序.
List<VideoModel> arrangeWeekItems(
  List<VideoModel> list, {
  required Set<String> followed,
  required Map<String, WeekUpdateTime> times,
  required bool sortByTime,
}) {
  final followedList = <VideoModel>[];
  final rest = <VideoModel>[];
  for (final video in list) {
    (followed.contains(video.hid) ? followedList : rest).add(video);
  }
  if (!sortByTime) {
    return [...followedList, ...rest];
  }
  return [
    ...sortByUpdateTime(followedList, times),
    ...sortByUpdateTime(rest, times),
  ];
}

/// 按更新时刻升序, 没有时刻的排在后面, 时刻相同时保持站点顺序.
///
/// `List.sort` 不保证稳定, 因此用原下标兜底.
List<VideoModel> sortByUpdateTime(
  List<VideoModel> list,
  Map<String, WeekUpdateTime> times,
) {
  final indexed = list.indexed.toList();
  indexed.sort((a, b) {
    final left = times[a.$2.hid]?.minutesOfDay;
    final right = times[b.$2.hid]?.minutesOfDay;
    if (left == null && right == null) {
      return a.$1 - b.$1;
    }
    if (left == null) {
      return 1;
    }
    if (right == null) {
      return -1;
    }
    if (left != right) {
      return left - right;
    }
    return a.$1 - b.$1;
  });
  return [for (final (_, video) in indexed) video];
}
