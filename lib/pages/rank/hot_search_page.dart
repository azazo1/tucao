import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tucao/common/widgets/loading_widget.dart';
import 'package:tucao/http/rank_http.dart';
import 'package:tucao/router/routes.dart';
import 'package:tucao/utils/logger.dart';

/// 热搜榜页面控制器.
class HotSearchController extends GetxController {
  final list = <HotKeyword>[].obs;

  final firstLoading = true.obs;

  final error = RxnString();

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

  Future<void> _fetch() async {
    error.value = null;
    try {
      list.assignAll(await RankHttp.fetchHotSearch());
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
        final list = _controller.list;
        return RefreshIndicator(
          onRefresh: _controller.refreshList,
          child: list.isEmpty
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: const [
                    SizedBox(height: 120),
                    EmptyWidget(message: '暂时没有热搜'),
                  ],
                )
              : ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: list.length,
                  separatorBuilder: (context, index) => const Divider(),
                  itemBuilder: (context, index) =>
                      _HotItem(item: list[index]),
                ),
        );
      }),
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
