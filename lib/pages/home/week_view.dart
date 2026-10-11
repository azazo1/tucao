import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tucao/common/widgets/loading_widget.dart';
import 'package:tucao/common/widgets/video_card.dart';
import 'package:tucao/http/week_http.dart';
import 'package:tucao/models/video.dart';
import 'package:tucao/pages/home/week_controller.dart';
import 'package:tucao/pages/video/video_page.dart';

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

  late final WeekController _controller = Get.put(
    WeekController(),
    tag: _tag,
  );

  @override
  bool get wantKeepAlive => true;

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
    return Obx(() {
      if (_controller.firstLoading.value) {
        return const LoadingWidget();
      }
      final error = _controller.error.value;
      if (error != null) {
        return ErrorWidgetView(message: error, onRetry: _controller.load);
      }
      final groups = _controller.groups;
      final index = _controller.index.value.clamp(0, groups.length - 1);
      final current = groups[index];

      return Column(
        children: [
          _WeekTabBar(
            groups: groups,
            index: index,
            onChanged: _controller.changeIndex,
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _controller.refreshList,
              child: current.list.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: const [
                        SizedBox(height: 120),
                        EmptyWidget(message: '这一天还没有更新'),
                      ],
                    )
                  : GridView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            mainAxisSpacing: 14,
                            crossAxisSpacing: 10,
                            childAspectRatio: 0.68,
                          ),
                      itemCount: current.list.length,
                      itemBuilder: (context, i) =>
                          _WeekCard(video: current.list[i]),
                    ),
            ),
          ),
        ],
      );
    });
  }
}

/// 分组切换条, 当天用主色标出.
class _WeekTabBar extends StatelessWidget {
  const _WeekTabBar({
    required this.groups,
    required this.index,
    required this.onChanged,
  });

  final List<WeekGroup> groups;
  final int index;
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
                child: Text(
                  groups[i].title,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
                    color: selected ? scheme.primary : null,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 时间表卡片, 在通用竖版卡片基础上补上集数状态与题材.
class _WeekCard extends StatelessWidget {
  const _WeekCard({required this.video});

  final VideoModel video;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return InkWell(
      onTap: () => VideoPage.open(video),
      borderRadius: BorderRadius.circular(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          VideoCover(
            url: video.cover,
            aspectRatio: 320 / 428,
            overlay: video.description.isEmpty
                ? null
                : CoverBadge(text: video.description),
          ),
          const SizedBox(height: 6),
          Text(
            video.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(height: 1.3),
          ),
          const SizedBox(height: 3),
          Row(
            children: [
              Text(
                '${video.playCount}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              if (video.keywords.isNotEmpty)
                Text(
                  video.keywords,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.primary,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
