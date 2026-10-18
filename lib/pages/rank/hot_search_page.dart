import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tucao/common/widgets/channel_bar.dart';
import 'package:tucao/common/widgets/loading_widget.dart';
import 'package:tucao/http/rank_http.dart';
import 'package:tucao/router/routes.dart';
import 'package:tucao/utils/logger.dart';

/// 热搜榜页面控制器.
///
/// 站点把热搜按今天 / 本周 / 本月 / 今年分组, 每组各自从 1 排名.
class HotSearchController extends GetxController {
  /// 按页面顺序保存的全部分组.
  final groups = <HotSearchGroup>[].obs;

  /// 当前选中的分组下标.
  final selected = 0.obs;

  final firstLoading = true.obs;

  final error = RxnString();

  /// 当前分组的条目, 分组为空时返回空列表.
  List<HotKeyword> get currentList =>
      selected.value < groups.length ? groups[selected.value].list : const [];

  @override
  void onInit() {
    super.onInit();
    load();
  }

  Future<void> load() async {
    firstLoading.value = true;
    await _fetch();
  }

  Future<void> refreshList() => _fetch();

  /// 切换分组, 下标越界时忽略.
  void selectGroup(int index) {
    if (index < 0 || index >= groups.length || index == selected.value) {
      return;
    }
    selected.value = index;
  }

  Future<void> _fetch() async {
    error.value = null;
    try {
      final data = await RankHttp.fetchHotSearch();
      groups.assignAll(data);
      if (selected.value >= data.length) {
        selected.value = 0;
      }
    } catch (e, stackTrace) {
      Log.e('加载热搜榜失败', error: e, stackTrace: stackTrace);
      error.value = e.toString();
    } finally {
      firstLoading.value = false;
    }
  }
}

/// 热搜榜页面.
///
/// 该榜单是关键词而不是视频, 点按后用关键词发起搜索.
class HotSearchPage extends StatefulWidget {
  const HotSearchPage({super.key});

  @override
  State<HotSearchPage> createState() => _HotSearchPageState();
}

class _HotSearchPageState extends State<HotSearchPage> {
  late final String _tag = 'hot_search_${identityHashCode(this)}';

  late final HotSearchController _controller = Get.put(
    HotSearchController(),
    tag: _tag,
  );

  @override
  void dispose() {
    if (Get.isRegistered<HotSearchController>(tag: _tag)) {
      Get.delete<HotSearchController>(tag: _tag);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('热搜榜')),
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
          return _buildEmpty();
        }
        final list = _controller.currentList;
        return Column(
          children: [
            if (groups.length > 1)
              SortBar(
                options: [
                  for (var index = 0; index < groups.length; index++)
                    SortOption(
                      label: groups[index].title,
                      value: index.toString(),
                    ),
                ],
                current: _controller.selected.value.toString(),
                onChanged: (value) {
                  final index = int.tryParse(value ?? '');
                  if (index != null) {
                    _controller.selectGroup(index);
                  }
                },
              ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _controller.refreshList,
                child: list.isEmpty
                    ? const _EmptyHotSearch()
                    : ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        itemCount: list.length,
                        separatorBuilder: (context, index) => const Divider(),
                        itemBuilder: (context, index) =>
                            _HotItem(item: list[index]),
                      ),
              ),
            ),
          ],
        );
      }),
    );
  }

  Widget _buildEmpty() {
    return RefreshIndicator(
      onRefresh: _controller.refreshList,
      child: const _EmptyHotSearch(),
    );
  }
}

class _EmptyHotSearch extends StatelessWidget {
  const _EmptyHotSearch();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: const [
        SizedBox(height: 120),
        EmptyWidget(message: '暂时没有热搜'),
      ],
    );
  }
}

class _HotItem extends StatelessWidget {
  const _HotItem({required this.item});

  final HotKeyword item;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // 前三名用主色强调, 与站点榜单一致.
    final highlight = item.rank <= 3;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: SizedBox(
        width: 28,
        child: Text(
          '${item.rank}',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: highlight ? scheme.primary : scheme.onSurfaceVariant,
          ),
        ),
      ),
      title: Text(item.keyword),
      trailing: Text(
        '${item.count}次',
        style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
      ),
      onTap: () => Get.toNamed(
        Routes.search,
        parameters: {'keyword': item.keyword},
      ),
    );
  }
}
