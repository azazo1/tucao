import 'package:get/get.dart';
import 'package:tucao/common/widgets/channel_bar.dart';
import 'package:tucao/http/rank_http.dart';
import 'package:tucao/models/video.dart';

/// 排行榜页控制器.
///
/// 榜单页面一次返回全部时间维度, 切换维度优先用已经拿到的数据,
/// 同时在后台按新的维度参数重新拉一次, 保证刷新到最新排名.
class RankPageController extends GetxController {
  /// 当前榜单类型.
  final type = RankType.hot.obs;

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

  /// 可选分区.
  ///
  /// 站点排行榜只接受这几个分区, 其余分区会返回空榜单, 因此不列出.
  static const rankChannels = <ChannelItem>[
    ChannelItem(id: 11, name: '连载新番'),
    ChannelItem(id: 43, name: '天朝出品'),
    ChannelItem(id: 26, name: '剧场版'),
    ChannelItem(id: 10, name: '完结番组'),
    ChannelItem(id: 39, name: '电视剧'),
    ChannelItem(id: 38, name: '电影'),
  ];

  /// 可选分区, 与站点排行榜页面保持一致.
  late final List<ChannelItem> channels = rankChannels;

  /// 时间维度选择条.
  static const periodOptions = [
    SortOption(label: '今天', value: '0'),
    SortOption(label: '本周', value: '1'),
    SortOption(label: '本月', value: '2'),
    SortOption(label: '今年', value: '3'),
  ];

  /// 当前榜单是否按时间维度分组.
  ///
  /// 排行榜与几个按热度排的榜单用今天/本周/本月/今年, 无人区这类按分区分组,
  /// 分组名不是时间维度, 此时改按分组下标切换.
  bool get hasPeriod => groups.isNotEmpty && groups.every((e) => e.period >= 0);

  /// 当前榜单类型是否支持分区筛选.
  bool get hasChannel => type.value.supportsChannel;

  /// 非时间维度榜单的分组选择条, 例如无人区按分区列出.
  List<SortOption> get groupOptions => [
    for (var i = 0; i < groups.length; i++)
      SortOption(label: groups[i].title, value: i.toString()),
  ];

  /// 当前分组下标, 用于非时间维度榜单.
  final groupIndex = 0.obs;

  /// 当前维度下的榜单, 没有对应维度时回落到页面返回的第一个榜单.
  List<VideoModel> get list {
    if (groups.isEmpty) {
      // 分组为空时不能走 clamp, Dart 的 clamp 要求下界不大于上界,
      // clamp(0, -1) 会直接抛异常.
      return const [];
    }
    if (!hasPeriod) {
      final index = groupIndex.value.clamp(0, groups.length - 1);
      return groups[index].list;
    }
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

  /// 切换榜单类型.
  Future<void> changeRankType(RankType value) async {
    if (type.value == value) {
      return;
    }
    type.value = value;
    // 非排行榜不支持分区筛选, 切回时重置为全站.
    if (!value.supportsChannel) {
      typeId.value = null;
    }
    groups.clear();
    await load();
  }

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

  /// 切换分组, 用于非时间维度榜单.
  void changeGroup(int value) {
    if (value >= 0 && value < groups.length) {
      groupIndex.value = value;
    }
  }

  Future<void> _fetch() async {
    loading.value = true;
    error.value = null;
    try {
      final result = await RankHttp.fetch(
        typeId: typeId.value,
        period: period.value,
        type: type.value,
      );
      groups.assignAll(result);
      groupIndex.value = 0;
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
