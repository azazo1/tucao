import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tucao/common/widgets/channel_bar.dart';
import 'package:tucao/common/widgets/loading_widget.dart';
import 'package:tucao/common/widgets/video_card.dart';
import 'package:tucao/models/video.dart';
import 'package:tucao/pages/bgm/bgm_index_controller.dart';

/// 番组索引页, 即站点的新番时间表.
///
/// 站点只提供 html, 数据由 [BgmHttp] 抓取. 顶部按年份与月份筛选,
/// 内容为两列网格, 卡片下方补充站点独有的集数状态与题材标签.
class BgmIndexPage extends StatefulWidget {
  const BgmIndexPage({super.key});

  @override
  State<BgmIndexPage> createState() => _BgmIndexPageState();
}

class _BgmIndexPageState extends State<BgmIndexPage> {
  /// 页面可能被重复打开, 用实例标识区分控制器.
  late final String _tag = 'bgm_${identityHashCode(this)}';

  late final BgmIndexController _controller = Get.put(
    BgmIndexController(),
    tag: _tag,
  );

  @override
  void dispose() {
    if (Get.isRegistered<BgmIndexController>(tag: _tag)) {
      Get.delete<BgmIndexController>(tag: _tag);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('新番索引')),
      body: Column(
        children: [
          _buildFilter(),
          const Divider(height: 1),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  /// 年份与月份筛选条.
  Widget _buildFilter() {
    final year = DateTime.now().year;
    return Obx(
      () => Column(
        children: [
          ChannelBar(
            channels: BgmIndexController.years(year),
            currentId: _controller.year.value,
            onChanged: _controller.changeYear,
          ),
          ChannelBar(
            channels: BgmIndexController.months,
            currentId: _controller.month.value,
            onChanged: _controller.changeMonth,
            showAll: true,
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    return Obx(() {
      final list = _controller.list;
      if (_controller.firstLoading.value) {
        return const LoadingWidget();
      }
      final error = _controller.error.value;
      if (error != null && list.isEmpty) {
        return ErrorWidgetView(message: error, onRetry: _controller.loadFirst);
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
              if (list.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyWidget(message: '这个月份还没有番组'),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                  sliver: SliverGrid(
                    gridDelegate: _gridDelegate(context),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => _buildCard(list[index]),
                      childCount: list.length,
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
    });
  }

  /// 卡片主体, 下方补充集数状态与题材标签.
  ///
  /// 这两项在解析时分别写进了 description 与 keywords.
  Widget _buildCard(VideoModel video) {
    final scheme = Theme.of(context).colorScheme;
    final state = video.description;
    final tags = video.keywords;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 卡片默认点击即进入播放页, 这里不再覆盖.
        VideoCardVertical(video: video),
        if (state.isNotEmpty || tags.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Row(
              children: [
                if (state.isNotEmpty)
                  Text(
                    state,
                    style: TextStyle(
                      fontSize: 11,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                if (state.isNotEmpty && tags.isNotEmpty)
                  const SizedBox(width: 6),
                if (tags.isNotEmpty)
                  Flexible(
                    child: Text(
                      tags,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: scheme.primary),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  /// 两列等宽网格, 高度按封面比例加上标题, 信息行与补充行估算.
  SliverGridDelegate _gridDelegate(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final itemWidth = (width - 24 - 10) / 2;
    return SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: 2,
      crossAxisSpacing: 10,
      mainAxisSpacing: 12,
      mainAxisExtent: itemWidth * 233 / 362 + 84,
    );
  }
}
