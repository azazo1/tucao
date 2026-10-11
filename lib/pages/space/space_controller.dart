import 'package:get/get.dart';
import 'package:tucao/http/space_http.dart';
import 'package:tucao/models/video.dart';
import 'package:tucao/utils/logger.dart';

/// 用户空间控制器.
class SpaceController extends GetxController {
  SpaceController(this.userId);

  final int userId;

  final info = Rxn<SpaceInfo>();

  final list = <VideoModel>[].obs;

  final page = 1.obs;

  final loading = false.obs;

  final firstLoading = true.obs;

  final error = RxnString();

  bool _hasMore = true;

  bool get hasMore => _hasMore;

  @override
  void onInit() {
    super.onInit();
    loadFirst();
  }

  Future<void> loadFirst() async {
    firstLoading.value = true;
    error.value = null;
    try {
      final result = await SpaceHttp.fetch(userId: userId, page: 1);
      info.value = result.info;
      list.assignAll(result.list);
      page.value = 1;
      _hasMore = result.hasMore;
    } catch (e, stackTrace) {
      Log.e('加载用户空间失败', error: e, stackTrace: stackTrace);
      error.value = e.toString();
    } finally {
      firstLoading.value = false;
    }
  }

  @override
  Future<void> refresh() async {
    error.value = null;
    try {
      final result = await SpaceHttp.fetch(userId: userId, page: 1);
      info.value = result.info;
      list.assignAll(result.list);
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
      final result = await SpaceHttp.fetch(userId: userId, page: next);
      if (result.list.isEmpty) {
        _hasMore = false;
      } else {
        // 分页之间可能重复推荐同一视频, 按 hid 去重后再追加.
        final exists = list.map((e) => e.hid).toSet();
        list.addAll(result.list.where((e) => !exists.contains(e.hid)));
        page.value = next;
        _hasMore = result.hasMore;
      }
    } catch (e) {
      error.value = e.toString();
    } finally {
      loading.value = false;
    }
  }
}
