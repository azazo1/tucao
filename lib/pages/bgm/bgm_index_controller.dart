import 'package:get/get.dart';
import 'package:tucao/common/controller/paging_controller.dart';
import 'package:tucao/common/widgets/channel_bar.dart';
import 'package:tucao/http/bgm_http.dart';
import 'package:tucao/models/video.dart';

/// 番组索引页控制器.
///
/// 月份与年份任意一项变化都从第一页重新拉取. 站点番组页没有可直接使用的
/// 总数, 每页固定 50 条, 返回不足一页即认为没有下一页, 因此这里覆盖
/// [hasMore], 不依赖基类的 total.
class BgmIndexController extends PagingController<VideoModel> {
  /// 当前月份, 1-12, 为空表示全部月份.
  final month = RxnInt();

  /// 当前年份.
  final year = RxnInt();

  bool _hasMore = true;

  @override
  bool get hasMore => _hasMore;

  /// 可选月份, "全部" 由 ChannelBar 的 showAll 提供.
  static final List<ChannelItem> months = [
    for (var i = 1; i <= 12; i++) ChannelItem(id: i, name: '$i月'),
  ];

  /// 可选年份, 只提供当前年份与上一年.
  static List<ChannelItem> years(int currentYear) => [
    ChannelItem(id: currentYear, name: '$currentYear年'),
    ChannelItem(id: currentYear - 1, name: '${currentYear - 1}年'),
  ];

  @override
  void onInit() {
    year.value = DateTime.now().year;
    super.onInit();
  }

  @override
  int get pageSize => BgmHttp.pageSize;

  @override
  Future<List<VideoModel>> fetchPage(int page) async {
    final result = await BgmHttp.fetch(
      month: month.value,
      year: year.value,
      page: page,
    );
    _hasMore = result.length >= BgmHttp.pageSize;
    return result;
  }

  /// 切换月份, 传 null 表示全部月份.
  Future<void> changeMonth(int? value) async {
    if (month.value == value) {
      return;
    }
    month.value = value;
    await _restart();
  }

  /// 切换年份.
  Future<void> changeYear(int? value) async {
    if (value == null || year.value == value) {
      return;
    }
    year.value = value;
    await _restart();
  }

  /// 筛选条件变化后从第一页重新加载.
  Future<void> _restart() async {
    // 先进入首屏加载, 避免清空列表时闪出空状态.
    firstLoading.value = true;
    _hasMore = true;
    await reload();
  }
}
