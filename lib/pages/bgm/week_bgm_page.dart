import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tucao/common/widgets/loading_widget.dart';
import 'package:tucao/common/widgets/video_card.dart';
import 'package:tucao/pages/bgm/week_bgm_controller.dart';

/// 本周新番页.
///
/// 按日期列出当天更新的番组, 与首页的时间表互补: 时间表按星期分组,
/// 这里按具体日期分组.
class WeekBgmPage extends StatefulWidget {
  const WeekBgmPage({super.key});

  @override
  State<WeekBgmPage> createState() => _WeekBgmPageState();
}

class _WeekBgmPageState extends State<WeekBgmPage> {
  late final String _tag = 'week_bgm_${identityHashCode(this)}';

  late final WeekBgmController _controller = Get.put(
    WeekBgmController(),
    tag: _tag,
  );

  @override
  void dispose() {
    if (Get.isRegistered<WeekBgmController>(tag: _tag)) {
      Get.delete<WeekBgmController>(tag: _tag);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('本周新番')),
      body: Obx(() {
        if (_controller.firstLoading.value) {
          return const LoadingWidget();
        }
        final error = _controller.error.value;
        if (error != null) {
          return ErrorWidgetView(message: error, onRetry: _controller.load);
        }
        final groups = _controller.groups;
        if (groups.isEmpty) {
          return const EmptyWidget(message: '本周还没有更新');
        }
        return RefreshIndicator(
          onRefresh: _controller.refresh,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              for (final group in groups) ...[
                SliverToBoxAdapter(child: _GroupHeader(title: group.title)),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  sliver: SliverList.separated(
                    itemCount: group.list.length,
                    separatorBuilder: (context, index) => const Divider(),
                    itemBuilder: (context, index) => VideoCardHorizontal(
                      video: group.list[index],
                    ),
                  ),
                ),
              ],
              const SliverToBoxAdapter(child: SizedBox(height: 16)),
            ],
          ),
        );
      }),
    );
  }
}

/// 日期分组标题.
class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 4),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 14,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
