import 'package:get/get.dart';
import 'package:tucao/common/controller/paging_controller.dart';
import 'package:tucao/common/widgets/channel_bar.dart';
import 'package:tucao/http/bgm_http.dart';
import 'package:tucao/models/video.dart';

/// 番组索引页控制器.
///
/// 站点提供季度, 年代与类型三组筛选, 任意一项变化都从第一页重新拉取.
/// 番组页每页固定 50 条, 是否还有下一页由基类按本页条数判断.
class BgmIndexController extends PagingController<VideoModel> {
  /// 季度, 对应站点的 month 参数, 为空表示不限.
  final month = RxnInt();

  /// 年代, 对应站点的 year 参数, 可以是四位年份或站点给出的区间.
  final year = RxnString();

  /// 题材, 对应站点的 types 参数, 为空表示不限.
  final types = RxnString();

  /// 季度筛选项, "全部" 由 ChannelBar 的 showAll 提供.
  static final List<ChannelItem> seasons = [
    for (var i = 0; i < BgmHttp.seasonOptions.length; i++)
      ChannelItem(id: i, name: BgmHttp.seasonOptions.keys.elementAt(i)),
  ];

  /// 年代筛选项, 站点给出的是区间与逐年两项混排.
  static final List<ChannelItem> years = [
    for (var i = 0; i < BgmHttp.yearOptions.length; i++)
      ChannelItem(id: i, name: BgmHttp.yearOptions[i]),
  ];

  @override
  int get pageSize => BgmHttp.pageSize;

  @override
  Future<List<VideoModel>> fetchPage(int page) async {
    return BgmHttp.fetch(
      month: month.value,
      year: year.value,
      types: types.value,
      page: page,
    );
  }

  /// 切换季度, 传 null 表示不限.
  Future<void> changeSeason(int? index) async {
    final value = index == null
        ? null
        : BgmHttp.seasonOptions.values.elementAt(index);
    if (month.value == value) {
      return;
    }
    month.value = value;
    await _restart();
  }

  /// 切换年代, 传 null 表示不限.
  Future<void> changeYear(int? index) async {
    final value = index == null ? null : BgmHttp.yearOptions[index];
    if (year.value == value) {
      return;
    }
    year.value = value;
    await _restart();
  }

  /// 按题材筛选, 传 null 表示不限.
  Future<void> changeTypes(String? value) async {
    if (types.value == value) {
      return;
    }
    types.value = value;
    await _restart();
  }

  /// 当前季度的下标, 供选择条高亮.
  int? get seasonIndex {
    final value = month.value;
    if (value == null) {
      return null;
    }
    final index = BgmHttp.seasonOptions.values.toList().indexOf(value);
    return index < 0 ? null : index;
  }

  /// 当前年代的下标, 供选择条高亮.
  int? get yearIndex {
    final value = year.value;
    if (value == null) {
      return null;
    }
    final index = BgmHttp.yearOptions.indexOf(value);
    return index < 0 ? null : index;
  }

  /// 筛选条件变化后从第一页重新加载.
  Future<void> _restart() async {
    // 先进入首屏加载, 避免清空列表时闪出空状态.
    firstLoading.value = true;
    await reload();
  }
}
