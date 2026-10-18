import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tucao/common/style.dart';
import 'package:tucao/common/widgets/channel_bar.dart';
import 'package:tucao/common/widgets/paging_list.dart';
import 'package:tucao/common/widgets/video_card.dart';
import 'package:tucao/models/video.dart';
import 'package:tucao/pages/search/search_controller.dart';
import 'package:tucao/pages/search/widgets/hot_search_section.dart';
import 'package:tucao/router/routes.dart';

/// 搜索页.
///
/// [embedded] 为 true 时作为主框架的 tab 使用, 不显示返回按钮.
/// 可以从路由参数 `keyword` 带关键词进入, 例如热搜榜的条目.
class SearchPage extends StatefulWidget {
  const SearchPage({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  /// 同一页面可能被多次打开, 用实例标识区分控制器.
  late final String _tag = 'search_${identityHashCode(this)}';

  late final SearchPageController _controller = Get.put(
    SearchPageController(),
    tag: _tag,
  );

  final _inputController = TextEditingController();
  final _focusNode = FocusNode();

  /// 当前关键词是否由路由参数带入.
  ///
  /// 从热搜榜点进来的搜索, 返回时应回到热搜榜;
  /// 在搜索页点热搜或手动搜索, 返回时先回到热搜与历史.
  bool _fromRouteKeyword = false;

  @override
  void initState() {
    super.initState();
    // 带关键词进入时直接发起搜索, 不再要求用户手动输入.
    final keyword = Get.parameters['keyword'];
    if (keyword != null && keyword.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _submit(keyword, fromRoute: true);
        }
      });
    }
  }

  @override
  void dispose() {
    _inputController.dispose();
    _focusNode.dispose();
    if (Get.isRegistered<SearchPageController>(tag: _tag)) {
      Get.delete<SearchPageController>(tag: _tag);
    }
    super.dispose();
  }

  Future<void> _submit(String value, {bool fromRoute = false}) async {
    if (_fromRouteKeyword != fromRoute && mounted) {
      setState(() => _fromRouteKeyword = fromRoute);
    }
    final keyword = value.trim();
    if (keyword.isEmpty) {
      _controller.clearKeyword();
      return;
    }
    if (_inputController.text != keyword) {
      _inputController.value = TextEditingValue(
        text: keyword,
        selection: TextSelection.collapsed(offset: keyword.length),
      );
    }
    _focusNode.unfocus();
    await _controller.search(keyword);
  }

  void _clearInput() {
    _inputController.clear();
    _controller.clearKeyword();
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      // 结果页的返回先回到热搜与历史, 再按一次才退出搜索页.
      // 带路由关键词进来的搜索保持原来的返回行为.
      final backToIdle =
          _controller.hasSearched && !_fromRouteKeyword && !widget.embedded;
      return PopScope(
        canPop: !backToIdle,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop && backToIdle) {
            _clearInput();
          }
        },
        child: Scaffold(
          appBar: AppBar(
            automaticallyImplyLeading: !widget.embedded,
            titleSpacing: widget.embedded ? 12 : 4,
            title: _buildInput(),
          ),
          body: Obx(() {
            if (_controller.hasSearched) {
              return _buildResult();
            }
            return _buildIdle();
          }),
        ),
      );
    });
  }

  Widget _buildInput() {
    return TextField(
      controller: _inputController,
      focusNode: _focusNode,
      textInputAction: TextInputAction.search,
      textAlignVertical: TextAlignVertical.center,
      style: const TextStyle(fontSize: 14),
      onChanged: (value) {
        // 手动清空输入框时回到搜索历史.
        if (value.isEmpty) {
          _controller.clearKeyword();
        }
      },
      onSubmitted: _submit,
      decoration: InputDecoration(
        hintText: '搜索视频',
        hintStyle: const TextStyle(fontSize: 14),
        prefixIcon: const Padding(
          padding: EdgeInsets.only(left: 12, right: 6),
          child: Icon(Icons.search, size: 20),
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
        suffixIcon: ValueListenableBuilder<TextEditingValue>(
          valueListenable: _inputController,
          builder: (context, value, child) {
            if (value.text.isEmpty) {
              return const SizedBox.shrink();
            }
            return IconButton(
              onPressed: _clearInput,
              tooltip: '清空',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
              icon: const Icon(Icons.cancel, size: 18),
            );
          },
        ),
        suffixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
      ),
    );
  }

  Widget _buildIdle() {
    return Obx(() {
      final items = _controller.history;
      // Obx 只订阅构建期读取过的可观察量. 热搜列表交给子组件渲染,
      // 这里先取一次快照, 否则数据回来之后界面不会刷新.
      final hotKeywords = _controller.hotSearch.toList();
      final scheme = Theme.of(context).colorScheme;
      return RefreshIndicator(
        onRefresh: _controller.loadHotSearch,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(vertical: 4),
          children: [
            Padding(
              padding: Style.pagePadding,
              child: Row(
                children: [
                  const Text('搜索历史', style: TextStyle(fontSize: 13)),
                  const Spacer(),
                  if (items.isNotEmpty)
                    TextButton(
                      onPressed: _controller.clearHistory,
                      child: const Text('清空'),
                    ),
                ],
              ),
            ),
            if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 12, 8),
                child: Text(
                  '还没有搜索记录',
                  style: TextStyle(fontSize: 13, color: scheme.outline),
                ),
              )
            else
              Padding(
                padding: Style.pagePadding,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 2,
                  children: [
                    for (final keyword in items)
                      InputChip(
                        label: Text(keyword),
                        labelStyle: const TextStyle(fontSize: 13),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        onPressed: () => _submit(keyword),
                        deleteIcon: const Icon(Icons.close, size: 15),
                        onDeleted: () => _controller.removeHistory(keyword),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            HotSearchSection(
              items: hotKeywords,
              onKeyword: _submit,
              onMore: () => Get.toNamed(Routes.hotSearch),
            ),
          ],
        ),
      );
    });
  }

  Widget _buildResult() {
    return Column(
      children: [
        ChannelBar(
          channels: _controller.channels,
          currentId: _controller.typeId.value,
          showAll: true,
          onChanged: _controller.changeType,
        ),
        SortBar(
          options: SortBar.videoSort,
          current: _controller.order.value,
          onChanged: _controller.changeOrder,
        ),
        Expanded(
          child: PagingList<VideoModel>(
            list: _controller.list,
            hasMore: _controller.hasMore,
            loading: _controller.loading.value,
            firstLoading: _controller.firstLoading.value,
            error: _controller.error.value,
            emptyMessage: '没有找到相关视频',
            onRefresh: _controller.refresh,
            onLoadMore: _controller.loadMore,
            onRetry: _controller.reload,
            itemBuilder: (context, video, index) =>
                VideoCardHorizontal(video: video),
          ),
        ),
      ],
    );
  }
}
