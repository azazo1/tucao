import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tucao/common/style.dart';
import 'package:tucao/common/widgets/channel_bar.dart';
import 'package:tucao/common/widgets/loading_widget.dart';
import 'package:tucao/common/widgets/video_card.dart';
import 'package:tucao/models/video.dart';
import 'package:tucao/pages/rank/rank_controller.dart';
import 'package:tucao/router/routes.dart';
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
        title: const Text('排行榜'),
      ),
      body: Column(
        children: [
          Obx(
            () => ChannelBar(
              channels: _controller.channels,
              currentId: _controller.typeId.value,
              showAll: true,
              allLabel: '全站',
              onChanged: _controller.changeType,
            ),
          ),
          Obx(
            () => SortBar(
              options: RankPageController.periodOptions,
              current: _controller.period.value.toString(),
              onChanged: (value) {
                final period = int.tryParse(value ?? '');
                if (period != null) {
                  _controller.changePeriod(period);
                }
              },
            ),
          ),
          Expanded(child: Obx(_buildBody)),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_controller.firstLoading.value) {
      return const LoadingWidget();
    }
    final error = _controller.error.value;
    if (error != null) {
      return ErrorWidgetView(message: error, onRetry: _controller.load);
    }
    final list = _controller.list;
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
              padding: const EdgeInsets.fromLTRB(12, 2, 12, 12),
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
