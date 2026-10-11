import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tucao/common/style.dart';
import 'package:tucao/common/widgets/channel_bar.dart';
import 'package:tucao/common/widgets/loading_widget.dart';
import 'package:tucao/common/widgets/video_card.dart';
import 'package:tucao/models/video.dart';
import 'package:tucao/pages/bgm/bgm_index_controller.dart';

/// 番组索引页, 即站点的番组库.
///
/// 站点只提供 html, 数据由 [BgmHttp] 抓取. 顶部提供季度, 年代与题材三组
/// 筛选, 内容为两列网格, 卡片下方补充站点独有的集数状态与题材标签.
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
      appBar: AppBar(
        title: const Text('番组索引'),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: '题材',
            onPressed: _showTypePicker,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildFilter(),
          const Divider(height: 1),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  /// 季度与年代筛选条.
  Widget _buildFilter() {
    return Obx(
      () => Column(
        children: [
          ChannelBar(
            channels: BgmIndexController.seasons,
            currentId: _controller.seasonIndex,
            onChanged: _controller.changeSeason,
            showAll: true,
            allLabel: '全部季度',
          ),
          ChannelBar(
            channels: BgmIndexController.years,
            currentId: _controller.yearIndex,
            onChanged: _controller.changeYear,
            showAll: true,
            allLabel: '全部年代',
          ),
          ChannelBar(
            channels: BgmIndexController.weekdays,
            currentId: _controller.weekdayIndex,
            onChanged: _controller.changeWeekday,
            showAll: true,
            allLabel: '全部星期',
          ),
        ],
      ),
    );
  }

  /// 题材筛选项较多, 用底部弹层承载.
  Future<void> _showTypePicker() async {
    final selected = await showModalBottomSheet<String?>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (context, scrollController) => ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Text('题材', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('不限'),
                  selected: _controller.types.value == null,
                  onSelected: (_) => Navigator.pop(context, ''),
                ),
                for (final type in _typeOptions)
                  ChoiceChip(
                    label: Text(type),
                    selected: _controller.types.value == type,
                    onSelected: (_) => Navigator.pop(context, type),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
    if (selected == null) {
      return;
    }
    await _controller.changeTypes(selected.isEmpty ? null : selected);
  }

  /// 站点题材列表, 取自番组页的 "类型" 一栏.
  static const _typeOptions = [
    '搞笑',
    '运动',
    '励志',
    '热血',
    '战斗',
    '竞技',
    '校园',
    '青春',
    '爱情',
    '恋爱',
    '冒险',
    '后宫',
    '百合',
    '治愈',
    '萝莉',
    '魔法',
    '悬疑',
    '推理',
    '奇幻',
    '科幻',
    '游戏',
    '神魔',
    '恐怖',
    '血腥',
    '机战',
    '战争',
    '犯罪',
    '历史',
    '社会',
    '职场',
    '剧情',
    '伪娘',
    '耽美',
    '童年',
    '教育',
    '亲子',
    '真人',
    '歌舞',
    '肉番',
    '美食',
    '美少女',
    '乙女向',
    '泡面番',
  ];

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
                  child: EmptyWidget(message: '没有符合条件的番组'),
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

  /// 卡片主体.
  ///
  /// 集数状态在解析时写进了 description, 这里作为封面角标展示.
  Widget _buildCard(VideoModel video) {
    return VideoCardVertical(
      video: video,
      badge: video.description.isEmpty ? null : video.description,
    );
  }

  /// 两列等宽网格, 卡片高度由 [Style.verticalCardExtent] 统一给出.
  SliverGridDelegate _gridDelegate(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final itemWidth = (width - 24 - 10) / 2;
    return SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: 2,
      crossAxisSpacing: 10,
      mainAxisSpacing: 12,
      mainAxisExtent: Style.verticalCardExtent(context, itemWidth),
    );
  }
}
