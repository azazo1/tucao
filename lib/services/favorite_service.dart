import 'package:get/get.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:tucao/models/favorite.dart';
import 'package:tucao/models/video.dart';
import 'package:tucao/utils/logger.dart';
import 'package:tucao/utils/storage.dart';

/// 官方客户端的 history/star 是本地收藏, 不要求登录, 不同步站点.
class FavoriteService extends GetxController {
  FavoriteService({Box? box}) : _storage = box;

  static FavoriteService get instance => Get.find<FavoriteService>();
  static const storageKey = 'local_favorites';
  static const storageVersion = 1;

  final Box? _storage;
  Box get _box => _storage ?? GStorage.history;
  final list = <FavoriteItem>[].obs;
  final loadError = RxnString();
  Future<void> _pending = Future<void>.value();

  @override
  void onInit() {
    super.onInit();
    reload();
  }

  /// 不识别的数据保留原样, 禁止随后写入覆盖它.
  void reload() {
    try {
      final raw = _box.get(storageKey);
      final entries = <FavoriteItem>[];
      if (raw != null) {
        if (raw is! Map || raw['version'] != storageVersion ||
            raw['items'] is! List) {
          throw const FormatException('本地收藏版本或格式不受支持');
        }
        final seen = <String>{};
        for (final item in raw['items'] as List) {
          if (item is! Map) {
            throw const FormatException('本地收藏记录格式无效');
          }
          final entry = FavoriteItem.fromJson(item.cast<String, dynamic>());
          if (seen.add(entry.video.hid)) {
            entries.add(entry);
          }
        }
      }
      list.assignAll(entries);
      loadError.value = null;
    } catch (error, stackTrace) {
      loadError.value = '本地收藏读取失败, 原始记录已保留';
      Log.e('读取本地收藏失败', error: error, stackTrace: stackTrace);
    }
  }

  bool contains(String hid) => list.any((item) => item.video.hid == hid);

  /// 串行保存, 保存成功后才发布新状态, 避免失败时出现假成功.
  Future<T> _change<T>(T Function(List<FavoriteItem>) change) {
    final operation = _pending.then((_) async {
      if (loadError.value != null) {
        throw StateError(loadError.value!);
      }
      final next = list.toList();
      final result = change(next);
      await _box.put(storageKey, {
        'version': storageVersion,
        'items': next.map((item) => item.toJson()).toList(),
      });
      list.assignAll(next);
      Log.i('本地收藏保存成功, 共 ${next.length} 条');
      return result;
    });
    // 失败不能阻塞后续重试, 错误仍由当前调用方收到.
    _pending = operation.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return operation;
  }

  Future<void> add(VideoModel video) => _change((next) {
    if (!RegExp(r'^[0-9]+$').hasMatch(video.hid)) {
      throw ArgumentError('本地收藏需要有效的视频 id');
    }
    next.removeWhere((item) => item.video.hid == video.hid);
    next.insert(0, FavoriteItem(
      video: video,
      savedAt: DateTime.now().millisecondsSinceEpoch,
    ));
  });

  Future<void> remove(String hid) => _change((next) {
    next.removeWhere((item) => item.video.hid == hid);
  });

  Future<bool> toggle(VideoModel video) => _change((next) {
    if (!RegExp(r'^[0-9]+$').hasMatch(video.hid)) {
      throw ArgumentError('本地收藏需要有效的视频 id');
    }
    if (next.any((item) => item.video.hid == video.hid)) {
      next.removeWhere((item) => item.video.hid == video.hid);
      return false;
    }
    next.insert(0, FavoriteItem(
      video: video,
      savedAt: DateTime.now().millisecondsSinceEpoch,
    ));
    return true;
  });
}
