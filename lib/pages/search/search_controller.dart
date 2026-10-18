import 'dart:async';

import 'package:get/get.dart';
import 'package:tucao/common/controller/paging_controller.dart';
import 'package:tucao/common/widgets/channel_bar.dart';
import 'package:tucao/http/rank_http.dart';
import 'package:tucao/http/video_http.dart';
import 'package:tucao/models/api_response.dart';
import 'package:tucao/models/channel.dart';
import 'package:tucao/models/video.dart';
import 'package:tucao/utils/logger.dart';
import 'package:tucao/utils/storage.dart';
import 'package:tucao/utils/storage_pref.dart';

/// 搜索页控制器.
///
/// 关键词, 分区, 排序任意一项变化都从第一页重新拉取.
class SearchPageController extends PagingController<VideoModel> {
  /// 搜索历史在 box 中的存储键.
  static const String _historyKey = 'list';

  /// 当前生效的关键词, 为空表示还没有搜索过.
  final keyword = ''.obs;

  /// 分区过滤, 为空表示全部分区.
  final typeId = RxnInt();

  /// 排序方式, 取值 date / mukio / views.
  final order = 'date'.obs;

  /// 搜索历史, 最新的在最前.
  final history = <String>[].obs;

  /// 搜索页推荐的热搜关键词, 只取前十条.
  final hotSearch = <HotKeyword>[].obs;

  /// 推荐区展示的热搜条数.
  static const int hotSearchLimit = 10;

  /// 可选分区, 取自首页分区树.
  late final List<ChannelItem> channels = [
    for (final channel in ChannelData.homeTabs)
      ChannelItem(id: channel.id, name: channel.name),
  ];

  @override
  void onInit() {
    // 没有关键词时 fetchPage 直接返回空列表, 基类的首屏加载不会发起请求,
    // 因此照常调用, 只是额外把本地的搜索历史读回来.
    super.onInit();
    loadHistory();
    unawaited(loadHotSearch());
  }

  @override
  int get pageSize => 20;

  /// 是否已经发起过搜索.
  bool get hasSearched => keyword.value.isNotEmpty;

  @override
  Future<List<VideoModel>> fetchPage(int page) async {
    final value = keyword.value;
    if (value.isEmpty) {
      total.value = 0;
      return const [];
    }
    final response = await VideoHttp.search(
      keyword: value,
      page: page,
      typeId: typeId.value,
      pageSize: pageSize,
      order: order.value,
    );
    if (!response.success) {
      throw ApiException(response.message ?? '搜索失败', code: response.code);
    }
    total.value = response.total;
    return response.list;
  }

  /// 提交关键词并重新搜索.
  Future<void> search(String value) async {
    final kw = value.trim();
    if (kw.isEmpty) {
      return;
    }
    keyword.value = kw;
    // 关键词一变化界面就会切到结果区, 先进入首屏加载, 避免闪出空状态.
    firstLoading.value = true;
    await addHistory(kw);
    await _restart();
  }

  /// 切换分区过滤, 传 null 表示全部.
  Future<void> changeType(int? value) async {
    if (typeId.value == value) {
      return;
    }
    typeId.value = value;
    if (!hasSearched) {
      return;
    }
    await _restart();
  }

  /// 切换排序方式.
  Future<void> changeOrder(String? value) async {
    if (value == null || value == order.value) {
      return;
    }
    order.value = value;
    if (!hasSearched) {
      return;
    }
    await _restart();
  }

  /// 清空关键词, 页面回到搜索历史.
  void clearKeyword() {
    keyword.value = '';
    error.value = null;
  }

  /// 从 box 读取搜索历史.
  void loadHistory() {
    final raw = GStorage.searchHistory.get(_historyKey);
    if (raw is List) {
      history.assignAll(
        raw.map((e) => e.toString()).where((e) => e.isNotEmpty),
      );
    }
  }

  /// 拉取热搜用于推荐区.
  ///
  /// 热搜只是搜索页的补充内容, 失败时保留空列表, 不打断手动搜索.
  Future<void> loadHotSearch() async {
    try {
      final list = await RankHttp.fetchHotSearch();
      hotSearch.assignAll(list.take(hotSearchLimit).toList());
    } catch (e, stackTrace) {
      Log.e('加载热搜失败', error: e, stackTrace: stackTrace);
    }
  }

  /// 记录一条搜索历史, 去掉重复项后放在最前, 超出上限时截断.
  Future<void> addHistory(String value) async {
    final kw = value.trim();
    if (kw.isEmpty) {
      return;
    }
    history.remove(kw);
    history.insert(0, kw);
    final limit = Pref.searchHistoryLimit;
    if (limit > 0 && history.length > limit) {
      history.removeRange(limit, history.length);
    }
    await _save();
  }

  /// 删除单条搜索历史.
  Future<void> removeHistory(String value) async {
    history.remove(value);
    await _save();
  }

  /// 清空搜索历史.
  Future<void> clearHistory() async {
    history.clear();
    await _save();
  }

  /// 条件变化后从第一页重新加载.
  Future<void> _restart() async {
    // 先进入首屏加载状态, 避免清空列表时闪出空状态.
    firstLoading.value = true;
    await reload();
  }

  Future<void> _save() async {
    await GStorage.searchHistory.put(_historyKey, history.toList());
  }
}
