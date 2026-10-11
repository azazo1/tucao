import 'package:get/get.dart';
import 'package:tucao/http/week_bgm_http.dart';
import 'package:tucao/utils/logger.dart';

/// 本周新番控制器.
class WeekBgmController extends GetxController {
  final groups = <WeekBgmGroup>[].obs;

  final loading = false.obs;

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

  @override
  Future<void> refresh() => _fetch();

  Future<void> _fetch() async {
    loading.value = true;
    error.value = null;
    try {
      final result = await WeekBgmHttp.fetch();
      groups.assignAll(result);
    } catch (e, stackTrace) {
      Log.e('加载本周新番失败', error: e, stackTrace: stackTrace);
      error.value = e.toString();
    } finally {
      loading.value = false;
      firstLoading.value = false;
    }
  }
}
