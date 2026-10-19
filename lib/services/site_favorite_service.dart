import 'package:get/get.dart';
import 'package:tucao/http/favorite_http.dart';
import 'package:tucao/models/site_favorite.dart';
import 'package:tucao/models/video.dart';
import 'package:tucao/utils/logger.dart';

/// 站点账号的追番 (官网叫收藏).
///
/// 站点没有查询单条状态的接口, 是否已追番只能整份读会员中心的追番夹页面,
/// 因此这里把整份列表缓存在内存里, 播放页与我的收藏页共用同一份;
/// 新增与取消完成后都重新拉取, 记录号与列表顺序以站点为准.
class SiteFavoriteService extends GetxController {
  /// 取当前实例, 没有注册时按需建一个.
  ///
  /// 追番状态是附属信息, 单独打开的页面与被测试的页面里也可能用到它,
  /// 因此不像本地收藏那样要求调用方先注册.
  static SiteFavoriteService get instance {
    if (!Get.isRegistered<SiteFavoriteService>()) {
      Get.put(SiteFavoriteService(), permanent: true);
    }
    return Get.find<SiteFavoriteService>();
  }

  /// 上一次拉取失败后的冷却时间, 避免登录失效时每个播放页都打一次站点.
  static const _retryDelay = Duration(seconds: 30);

  final list = <SiteFavoriteItem>[].obs;

  /// 正在拉取追番夹.
  final loading = false.obs;

  /// 最近一次失败的原因, 成功时为空.
  final error = RxnString();

  bool _loaded = false;
  DateTime? _failedAt;

  /// 是否已经成功拉到过列表, 没拉到过时状态是不可信的.
  bool get loaded => _loaded;

  /// 站点账号里是否已追番.
  bool contains(String hid) => find(hid) != null;

  /// 找到该视频的追番记录, 取消时要用它的记录号.
  SiteFavoriteItem? find(String hid) {
    if (hid.isEmpty) {
      return null;
    }
    for (final item in list) {
      if (item.hid == hid) {
        return item;
      }
    }
    return null;
  }

  /// 记录已经被站点删掉, 或者账号已退出登录时丢掉缓存.
  void clear() {
    list.clear();
    _loaded = false;
    _failedAt = null;
    error.value = null;
  }

  /// 没拉到过时拉一次, 播放页进入时调用.
  ///
  /// 已经拉到过就不再请求, 想强刷用 [refresh].
  Future<void> ensureLoaded() async {
    if (_loaded) {
      return;
    }
    await refresh();
  }

  /// 整份拉取, 失败只记录原因并等待下次重试, 列表保持上一次的内容.
  Future<void> refresh({bool force = false}) async {
    if (loading.value) {
      return;
    }
    if (!force) {
      if (_loaded) {
        return;
      }
      final failedAt = _failedAt;
      if (failedAt != null &&
          DateTime.now().difference(failedAt) < _retryDelay) {
        return;
      }
    }
    loading.value = true;
    try {
      final items = await FavoriteHttp.fetchFolder();
      list.assignAll(items);
      _loaded = true;
      _failedAt = null;
      error.value = null;
      Log.i('站点追番共 ${items.length} 条');
    } catch (e) {
      _failedAt = DateTime.now();
      error.value = _describe(e);
      Log.d('读取站点追番失败: $e');
    } finally {
      loading.value = false;
    }
  }

  /// 新增追番.
  ///
  /// 记录号只有追番夹页面里才有, 因此新增成功后跟着拉一次列表,
  /// 拉取失败不影响追番本身已经生效.
  Future<void> add(VideoModel video) async {
    await FavoriteHttp.add(video: video);
    await refresh(force: true);
  }

  /// 取消追番, 站点没确认时按失败抛出.
  Future<void> remove(SiteFavoriteItem item) async {
    await FavoriteHttp.remove(recordId: item.recordId);
    final items = await FavoriteHttp.fetchFolder();
    if (items.any((entry) => entry.recordId == item.recordId)) {
      throw StateError('站点未确认取消追番, 请稍后重试');
    }
    list.assignAll(items);
    _loaded = true;
    _failedAt = null;
    error.value = null;
    Log.i('已取消追番 ${item.title}');
  }

  /// 把异常换成直接能给用户看的一句话.
  ///
  /// 网络层抛的是 StateError, 它的 toString 前面带一节 "Bad state: ",
  /// 放在提示里很扎眼, 因此这里剥掉前缀.
  static String _describe(Object error) {
    const prefix = 'Bad state: ';
    final text = error.toString();
    if (text.startsWith(prefix)) {
      return text.substring(prefix.length);
    }
    return '站点追番读取失败, 请稍后重试';
  }
}
