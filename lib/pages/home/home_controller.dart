import 'package:get/get.dart';
import 'package:tucao/pages/channel/channel_controller.dart';

/// 首页的分区控制器集合.
///
/// 首页每个分区一个 [ChannelController], 按 tid 缓存,
/// 切换 tab 或子分区时复用已经加载的数据, 不重复请求.
class HomeController extends GetxController {
  final _controllers = <int, ChannelController>{};

  /// 注册标签, 与分区页的同名控制器区分开.
  static String tagOf(int tid) => 'home_channel_$tid';

  /// 取得分区控制器, 首次访问时创建并开始加载.
  ChannelController of(int tid) {
    final cached = _controllers[tid];
    if (cached != null) {
      return cached;
    }
    final tag = tagOf(tid);
    final controller = Get.isRegistered<ChannelController>(tag: tag)
        ? Get.find<ChannelController>(tag: tag)
        : Get.put(ChannelController(typeId: tid), tag: tag);
    _controllers[tid] = controller;
    return controller;
  }

  @override
  void onClose() {
    for (final tid in _controllers.keys.toList()) {
      if (Get.isRegistered<ChannelController>(tag: tagOf(tid))) {
        Get.delete<ChannelController>(tag: tagOf(tid));
      }
    }
    _controllers.clear();
    super.onClose();
  }
}
