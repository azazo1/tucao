import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tucao/common/adaptive.dart';
import 'package:tucao/common/style.dart';
import 'package:tucao/common/widgets/channel_bar.dart';
import 'package:tucao/common/widgets/loading_widget.dart';
import 'package:tucao/common/widgets/video_block_sheet.dart';
import 'package:tucao/common/widgets/video_card.dart';
import 'package:tucao/http/rank_http.dart';
import 'package:tucao/models/video.dart';
import 'package:tucao/pages/rank/rank_controller.dart';
import 'package:tucao/router/routes.dart';
import 'package:tucao/services/block_service.dart';
import 'package:tucao/utils/utils.dart';

/// 排行榜页.
///
/// [embedded] 为 true 时作为主框架的 tab 使用, 不显示返回按钮.
class RankPage extends StatefulWidget {
  const RankPage({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<RankPage> createState() => _RankPageState();
}

class _RankPageState extends State<RankPage> {
  /// 同一页面可能被多次打开, 用实例标识区分控制器.
  late final String _tag = 'rank_${identityHashCode(this)}';

  late final RankPageController _controller = Get.put(
    RankPageController(),
    tag: _tag,
  );

  @override
  void dispose() {
    if (Get.isRegistered<RankPageController>(tag: _tag)) {
      Get.delete<RankPageController>(tag: _tag);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !widget.embedded,
        // 榜单类型有八项, 放在标题栏作为下拉选择, 避免顶部叠加三层横向滚动条.
        title: Obx(
          () => PopupMenuButton<RankType>(
            tooltip: '切换榜单',
            initialValue: _controller.type.value,
            onSelected: _controller.changeRankType,
            itemBuilder: (context) => [
              for (final item in RankType.values)
                PopupMenuItem(value: item, child: Text(item.label)),
            ],
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_controller.type.value.label),
                const Icon(Icons.arrow_drop_down),
              ],
            ),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.group_outlined),
            tooltip: 'u榜',
            onPressed: () => Get.toNamed(Routes.userRank),
          ),
          IconButton(
            icon: const Icon(Icons.local_fire_department_outlined),
            tooltip: '热搜榜',
            onPressed: () => Get.toNamed(Routes.hotSearch),
          ),
        ],
      ),
      body: Column(
        children: [
          Obx(
            () => _controller.hasChannel
                ? ChannelBar(
                    channels: _controller.channels,
                    currentId: _controller.typeId.value,
                    showAll: true,
                    allLabel: '全站',
                    onChanged: _controller.changeType,
                  )
                : const SizedBox.shrink(),
          ),
          Obx(
            () => _controller.hasPeriod
                ? SortBar(
                    options: RankPageController.periodOptions,
                    current: _controller.period.value.toString(),
                    onChanged: (value) {
                      final period = int.tryParse(value ?? '');
                      if (period != null) {
                        _controller.changePeriod(period);
                      }
                    },
                  )
                : _controller.groups.length > 1
                ? ChannelBar(
                    channels: [
                      for (var i = 0; i < _controller.groups.length; i++)
                        ChannelItem(
                          id: i,
                          name: _controller.groups[i].title,
                        ),
                    ],
                    currentId: _controller.groupIndex.value,
                    onChanged: (value) {
                      if (value != null) {
                        _controller.changeGroup(value);
                      }
                    },
                  )
                : const SizedBox.shrink(),
          ),
          Expanded(child: Obx(() => _buildBody(context))),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_controller.firstLoading.value) {
      return const LoadingWidget();
    }
    final error = _controller.error.value;
    if (error != null) {
      return ErrorWidgetView(message: error, onRetry: _controller.load);
    }
    final list = _controller.list.withoutBlocked();
    // 平板与横屏下把榜单收窄居中, 避免一行文字过长.
    final side = Adaptive.sidePadding(
      context,
      maxWidth: Adaptive.listMaxWidth,
    );
    return RefreshIndicator(
      onRefresh: _controller.refreshList,
      child: list.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                SizedBox(height: 120),
                EmptyWidget(message: '这个榜单还没有内容'),
              ],
            )
          : ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(side + 12, 2, side + 12, 12),
              itemCount: list.length,
              separatorBuilder: (context, index) => const Divider(),
              itemBuilder: (context, index) =>
                  _RankItem(video: list[index], rank: index + 1),
            ),
    );
  }
}

/// 单条排行记录, 比通用横版卡片更紧凑, 左侧是排名.
class _RankItem extends StatelessWidget {
  const _RankItem({required this.video, required this.rank});

  final VideoModel video;
  final int rank;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // 前三名用主色突出, 与站点的 n123 样式一致.
    final highlight = rank <= 3;
    return InkWell(
      onTap: () => Get.toNamed(Routes.video, parameters: {'hid': video.hid}),
      onLongPress: () => showVideoBlockSheet(context, video),
      borderRadius: BorderRadius.circular(Style.cardRadius),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 26,
              child: Text(
                '$rank',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: highlight ? scheme.primary : scheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(width: 6),
            SizedBox(
              width: 112,
              child: VideoCover(url: video.cover, radius: 6),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    video.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      height: 1.3,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(
                        Icons.play_circle_outline,
                        size: 13,
                        color: scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        Utils.formatCount(video.playCount),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      if (video.userName.isNotEmpty) ...[
                        const SizedBox(width: 10),
                        Flexible(
                          child: Text(
                            video.userName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
