import 'package:get/get.dart';
import 'package:tucao/http/article_http.dart';
import 'package:tucao/utils/logger.dart';

/// 档案页控制器.
class ArticleController extends GetxController {
  /// 每页固定条数, 由页面决定, 这里不做分页累加以外的处理.
  final list = <ArticleModel>[].obs;

  final page = 1.obs;

  final total = 0.obs;

  final loading = false.obs;

  final firstLoading = true.obs;

  final error = RxnString();

  /// 当前分类, 为空表示全部.
  final keyword = RxnString();

  bool _hasMore = true;

  bool get hasMore => _hasMore;

  /// 分类选择条.
  static const categoryOptions = ArticleHttp.categories;

  @override
  void onInit() {
    super.onInit();
    loadFirst();
  }

  Future<void> loadFirst() async {
    firstLoading.value = true;
    error.value = null;
    try {
      final result = await ArticleHttp.fetch(page: 1, keyword: keyword.value);
      list.assignAll(result.list);
      total.value = result.total;
      page.value = 1;
      _hasMore = result.hasMore;
    } catch (e, stackTrace) {
      Log.e('加载档案失败', error: e, stackTrace: stackTrace);
      error.value = e.toString();
    } finally {
      firstLoading.value = false;
    }
  }

  @override
  Future<void> refresh() async {
    error.value = null;
    try {
      final result = await ArticleHttp.fetch(page: 1, keyword: keyword.value);
      list.assignAll(result.list);
      total.value = result.total;
      page.value = 1;
      _hasMore = result.hasMore;
    } catch (e) {
      error.value = e.toString();
    }
  }

  Future<void> loadMore() async {
    if (loading.value || !_hasMore) {
      return;
    }
    loading.value = true;
    try {
      final next = page.value + 1;
      final result = await ArticleHttp.fetch(
        page: next,
        keyword: keyword.value,
      );
      if (result.list.isEmpty) {
        _hasMore = false;
      } else {
        list.addAll(result.list);
        page.value = next;
        _hasMore = result.hasMore;
      }
    } catch (e) {
      error.value = e.toString();
    } finally {
      loading.value = false;
    }
  }

  /// 切换分类.
  Future<void> changeCategory(String? value) async {
    if (keyword.value == value) {
      return;
    }
    keyword.value = value;
    list.clear();
    _hasMore = true;
    await loadFirst();
  }
}
