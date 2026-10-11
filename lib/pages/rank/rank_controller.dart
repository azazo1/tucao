import 'package:get/get.dart';
import 'package:tucao/common/widgets/channel_bar.dart';
import 'package:tucao/http/rank_http.dart';
import 'package:tucao/models/channel.dart';
import 'package:tucao/models/video.dart';

/// 排行榜页控制器.
///
/// 榜单页面一次返回全部时间维度, 切换维度优先用已经拿到的数据,
/// 同时在后台按新的维度参数重新拉一次, 保证刷新到最新排名.
class RankPageController extends GetxController {
  /// 当前分区, 为空表示全站.
  final typeId = RxnInt();

  /// 当前时间维度: 0 今天, 1 本周, 2 本月, 3 今年.
  final period = 0.obs;

  /// 接口返回的全部时间维度.
  final groups = <RankGroup>[].obs;

  final loading = false.obs;

  /// 是否处于首屏加载.
  final firstLoading = true.obs;

  final error = RxnString();

  /// 可选分区, 取自首页分区树.
  late final List<ChannelItem> channels = [
    for (final channel in ChannelData.homeTabs)
      ChannelItem(id: channel.id, name: channel.name),
  ];

  /// 时间维度选择条.
  static const periodOptions = [
    SortOption(label: '今天', value: '0'),
    SortOption(label: '本周', value: '1'),
    SortOption(label: '本月', value: '2'),
    SortOption(label: '今年', value: '3'),
  ];

  /// 当前维度下的榜单, 没有对应维度时回落到页面返回的第一个榜单.
  List<VideoModel> get list {
    for (final group in groups) {
      if (group.period == period.value) {
        return group.list;
      }
    }
    return groups.isEmpty ? const [] : groups.first.list;
  }

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
  ///
  /// 方法名避开 GetxController 自带的 refresh 与 reload.
  Future<void> refreshList() => _fetch();

  /// 切换分区, 传 null 表示全站.
  Future<void> changeType(int? value) async {
    if (typeId.value == value) {
      return;
    }
    typeId.value = value;
    groups.clear();
    await load();
  }

  /// 切换时间维度.
  Future<void> changePeriod(int value) async {
    if (period.value == value) {
      return;
    }
    period.value = value;
    await _fetch();
  }

  Future<void> _fetch() async {
    loading.value = true;
    error.value = null;
    try {
      final result = await RankHttp.fetch(
        typeId: typeId.value,
        period: period.value,
      );
      groups.assignAll(result);
    } catch (e) {
      // 切换维度失败时保留上一次的榜单, 只有无内容可显示才提示错误.
      if (groups.isEmpty) {
        error.value = e.toString();
      }
    } finally {
      loading.value = false;
      firstLoading.value = false;
    }
  }
}
