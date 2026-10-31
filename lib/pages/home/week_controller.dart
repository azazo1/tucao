import 'package:get/get.dart';
import 'package:tucao/http/week_http.dart';
import 'package:tucao/utils/logger.dart';

/// 首页新番时间表控制器.
class WeekController extends GetxController {
  final groups = <WeekGroup>[].obs;

  final loading = false.obs;

  final firstLoading = true.obs;

  final error = RxnString();

  /// 当前选中的分组下标.
  final index = 0.obs;

  /// 当前分组的列表, 没有数据时返回空列表.
  List<WeekGroup> get _groups => groups;

  @override
  void onInit() {
    super.onInit();
    load();
  }

  /// 首次加载与失败重试.
  Future<void> load() async {
    firstLoading.value = true;
    await _fetch();
  }

  /// 下拉刷新, 不遮挡已有内容.
  Future<void> refreshList() => _fetch();

  Future<void> _fetch() async {
    loading.value = true;
    error.value = null;
    try {
      final result = await WeekHttp.fetch();
      if (result.isEmpty) {
        error.value = '没有取到新番时间表';
      } else {
        // 已经有数据说明是刷新, 保留用户选中的分组, 不能把周几重置回今天.
        final keepIndex = _groups.isNotEmpty;
        groups.assignAll(result);
        if (keepIndex) {
          index.value = index.value.clamp(0, result.length - 1);
        } else {
          // 首次加载才跟随设备当前星期.
          index.value = todayIndex(result.length);
        }
      }
    } catch (e, stackTrace) {
      Log.e('加载新番时间表失败', error: e, stackTrace: stackTrace);
      error.value = e.toString();
    } finally {
      loading.value = false;
      firstLoading.value = false;
    }
  }

  /// 站点分组顺序是周日到周六, 把当前星期映射到对应下标.
  ///
  /// 时间表的分组切换条也用这个下标标出当天.
  static int todayIndex(int length) {
    // DateTime.weekday 里周一是 1, 周日是 7; 分组里周日是 0.
    final weekday = DateTime.now().weekday;
    final target = weekday == 7 ? 0 : weekday;
    return target < length ? target : 0;
  }

  void changeIndex(int value) {
    if (value >= 0 && value < _groups.length) {
      index.value = value;
    }
  }
}
