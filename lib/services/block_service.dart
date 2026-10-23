import 'package:get/get.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:tucao/models/blocked_video.dart';
import 'package:tucao/models/video.dart';
import 'package:tucao/utils/logger.dart';
import 'package:tucao/utils/storage.dart';

/// 番剧与视频的本地屏蔽.
///
/// 记录只保存在这台设备上, 不上报站点, 也不修改站点数据; 列表页与搜索在
/// 展示前过滤掉这些编号, 解除屏蔽后条目会重新出现.
class BlockService extends GetxController {
  BlockService({Box? box}) : _storage = box;

  /// 取当前实例, 没有注册时按需建一个.
  ///
  /// 被测试的页面与单独打开的页面也可能用到屏蔽状态, 因此不要求调用方
  /// 先注册服务.
  static BlockService get instance {
    if (!Get.isRegistered<BlockService>()) {
      Get.put(BlockService(), permanent: true);
    }
    return Get.find<BlockService>();
  }

  static const storageKey = 'blocked_videos';
  static const storageVersion = 1;

  final Box? _storage;

  Box? get _box {
    if (_storage != null) {
      return _storage;
    }
    // 测试里往往只准备了别的存储盒, 这时按空列表处理, 不把测试弄挂.
    return GStorage.initialized ? GStorage.blocked : null;
  }

  final list = <BlockedVideo>[].obs;

  final loadError = RxnString();

  Future<void> _pending = Future<void>.value();

  @override
  void onInit() {
    super.onInit();
    reload();
  }

  /// 读取本地记录. 不识别的数据保留原样, 禁止随后写入覆盖它.
  void reload() {
    final box = _box;
    if (box == null) {
      list.clear();
      loadError.value = null;
      return;
    }
    try {
      final raw = box.get(storageKey);
      final entries = <BlockedVideo>[];
      if (raw != null) {
        if (raw is! Map ||
            raw['version'] != storageVersion ||
            raw['items'] is! List) {
          throw const FormatException('本地屏蔽版本或格式不受支持');
        }
        final seen = <String>{};
        for (final item in raw['items'] as List) {
          if (item is! Map) {
            throw const FormatException('本地屏蔽记录格式无效');
          }
          final entry = BlockedVideo.fromJson(item.cast<String, dynamic>());
          if (seen.add(entry.hid)) {
            entries.add(entry);
          }
        }
      }
      list.assignAll(entries);
      loadError.value = null;
    } catch (error, stackTrace) {
      loadError.value = '本地屏蔽读取失败, 原始记录已保留';
      Log.e('读取本地屏蔽失败', error: error, stackTrace: stackTrace);
    }
  }

  /// 该编号是否已经被屏蔽.
  bool isBlocked(String hid) {
    if (hid.isEmpty) {
      return false;
    }
    for (final item in list) {
      if (item.hid == hid) {
        return true;
      }
    }
    return false;
  }

  /// 去掉已经被屏蔽的条目.
  ///
  /// 迭代 [list] 会登记响应式读取, 因此页面在 Obx 里调用它会跟着屏蔽变化刷新.
  List<VideoModel> visibleOf(Iterable<VideoModel> videos) {
    final hidden = <String>{for (final item in list) item.hid};
    if (hidden.isEmpty) {
      return videos.toList();
    }
    return [
      for (final video in videos)
        if (!hidden.contains(video.hid)) video,
    ];
  }

  /// 屏蔽一个视频或番剧, 重复屏蔽时保留最新标题与封面.
  Future<void> block(VideoModel video) => _change((next) {
    if (!RegExp(r'^[0-9]+$').hasMatch(video.hid)) {
      throw ArgumentError('屏蔽需要有效的视频 id');
    }
    next.removeWhere((item) => item.hid == video.hid);
    next.insert(0, BlockedVideo.fromVideo(video));
  });

  /// 解除一个编号的屏蔽.
  Future<void> unblock(String hid) => _change((next) {
    next.removeWhere((item) => item.hid == hid);
  });

  /// 解除全部屏蔽.
  Future<void> clear() => _change((next) => next.clear());

  /// 串行保存, 写盘成功后才发布新状态, 避免失败时出现假成功.
  Future<T> _change<T>(T Function(List<BlockedVideo>) change) {
    final operation = _pending.then((_) async {
      if (loadError.value != null) {
        throw StateError(loadError.value!);
      }
      final box = _box;
      if (box == null) {
        throw StateError('本地屏蔽存储未就绪');
      }
      final next = list.toList();
      final result = change(next);
      await box.put(storageKey, {
        'version': storageVersion,
        'items': next.map((item) => item.toJson()).toList(),
      });
      list.assignAll(next);
      Log.i('本地屏蔽保存成功, 共 ${next.length} 条');
      return result;
    });
    // 失败不能阻塞后续重试, 错误仍由当前调用方收到.
    _pending = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }
}

/// 列表在展示前统一去掉本机屏蔽的条目.
extension BlockedVideoFilter on Iterable<VideoModel> {
  List<VideoModel> withoutBlocked() => BlockService.instance.visibleOf(this);
}
