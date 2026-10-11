import 'package:get/get.dart';

/// 分页列表的状态基类.
///
/// 站点的列表接口都返回总数与当页数据, 分页逻辑一致,
/// 这里抽出来供各列表控制器复用.
abstract class PagingController<T> extends GetxController {
  /// 每页数量.
  int get pageSize => 20;

  final list = <T>[].obs;

  /// 当前页码, 从 1 开始.
  final page = 1.obs;

  final total = 0.obs;

  final loading = false.obs;

  /// 是否处于首屏加载.
  final firstLoading = true.obs;

  /// 首屏错误信息.
  final error = RxnString();

  bool get hasMore => list.length < total.value;

  /// 拉取一页数据, 由子类实现.
  Future<List<T>> fetchPage(int page);

  @override
  void onInit() {
    super.onInit();
    loadFirst();
  }

  /// 首次加载.
  Future<void> loadFirst() async {
    firstLoading.value = true;
    error.value = null;
    try {
      final result = await fetchPage(1);
      list.assignAll(result);
      page.value = 1;
    } catch (e) {
      error.value = e.toString();
    } finally {
      firstLoading.value = false;
    }
  }

  /// 下拉刷新.
  @override
  Future<void> refresh() async {
    error.value = null;
    try {
      final result = await fetchPage(1);
      list.assignAll(result);
      page.value = 1;
    } catch (e) {
      error.value = e.toString();
    }
  }

  /// 加载下一页.
  Future<void> loadMore() async {
    if (loading.value || !hasMore) {
      return;
    }
    loading.value = true;
    try {
      final next = page.value + 1;
      final result = await fetchPage(next);
      list.addAll(result);
      page.value = next;
    } catch (e) {
      error.value = e.toString();
    } finally {
      loading.value = false;
    }
  }

  /// 清空并重新加载, 用于切换筛选条件.
  Future<void> reload() async {
    list.clear();
    page.value = 1;
    total.value = 0;
    await loadFirst();
  }
}
