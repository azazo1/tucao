import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tucao/common/adaptive.dart';
import 'package:tucao/common/widgets/channel_bar.dart';
import 'package:tucao/common/widgets/paging_list.dart';
import 'package:tucao/common/widgets/video_card.dart';
import 'package:tucao/models/video.dart';
import 'package:tucao/pages/channel/channel_controller.dart';
import 'package:tucao/services/block_service.dart';

/// 单个分区的完整列表页.
///
/// 路由参数 `tid` 与 `name`, 由首页的分区入口和 "更多" 按钮进入.
class ChannelPage extends StatefulWidget {
  const ChannelPage({super.key});

  @override
  State<ChannelPage> createState() => _ChannelPageState();
}

class _ChannelPageState extends State<ChannelPage> {
  late final int _tid;
  late final String _name;
  late final ChannelController _controller;

  /// 当前排序, 与控制器内的 order 保持同步.
  late String? _order;

  @override
  void initState() {
    super.initState();
    final params = Get.parameters;
    _tid = int.tryParse(params['tid'] ?? '') ?? 0;
    _name = params['name'] ?? '分区';
    final tag = 'channel_$_tid';
    // 复用同一分区的控制器, 避免重复进入时丢掉已加载的数据.
    _controller = Get.isRegistered<ChannelController>(tag: tag)
        ? Get.find<ChannelController>(tag: tag)
        : Get.put(ChannelController(typeId: _tid), tag: tag);
    _order = _controller.order;
  }

  void _changeOrder(String? value) {
    if (value == null || value == _order) {
      return;
    }
    setState(() => _order = value);
    _controller.changeOrder(value);
  }

  @override
  Widget build(BuildContext context) {
    final side = Adaptive.sidePadding(
      context,
      maxWidth: Adaptive.listMaxWidth,
    );
    return Scaffold(
      appBar: AppBar(title: Text(_name)),
      body: Column(
        children: [
          SortBar(
            options: SortBar.videoSort,
            current: _order,
            onChanged: _changeOrder,
          ),
          const Divider(height: 1),
          Expanded(
            child: Obx(
              () => PagingList<VideoModel>(
                list: _controller.list.withoutBlocked(),
                onRefresh: _controller.refresh,
                onLoadMore: _controller.loadMore,
                hasMore: _controller.hasMore,
                loading: _controller.loading.value,
                firstLoading: _controller.firstLoading.value,
                error: _controller.error.value,
                onRetry: _controller.loadFirst,
                emptyMessage: '这个分区还没有视频',
                padding: EdgeInsets.symmetric(
                  horizontal: side + 12,
                  vertical: 4,
                ),
                separator: const Divider(height: 1, indent: 158),
                itemBuilder: (context, video, index) =>
                    VideoCardHorizontal(video: video),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
