import 'dart:async';

import 'package:tucao/models/danmaku_preferences.dart';
import 'package:tucao/utils/danmaku_preferences_migration.dart';
import 'package:tucao/utils/logger.dart';
import 'package:tucao/utils/storage.dart';

/// 单个 Hive 记录保存整个样式, 所有写入串行执行.
abstract final class DanmakuPreferencesStore {
  static const key = 'danmaku_preferences';
  static final _queues = Expando<_DanmakuWriteQueue>();
  static _DanmakuWriteQueue _queue(Object box) =>
      _queues[box] ??= _DanmakuWriteQueue();

  static bool _supported(Object? raw) =>
      raw is Map &&
      raw['version'] is int &&
      raw['version'] == DanmakuPreferences.version;

  static bool get hasUnsupportedVersion {
    final raw = GStorage.setting.get(key);
    return raw != null && !_supported(raw);
  }

  static DanmakuPreferences read() {
    final box = GStorage.setting;
    final raw = box.get(key);
    if (raw is Map && _supported(raw)) {
      return DanmakuPreferences.fromMap(raw);
    }
    if (raw != null) return DanmakuPreferences.defaults;
    final migrated = DanmakuPreferencesMigration.fromLegacy(box.get);
    final queue = _queue(box);
    if (!queue.migrationQueued) {
      queue.migrationQueued = true;
      unawaited(
        queue
            .enqueue(() async {
              // 前面的保存可能已经完成, 此时不再用旧数据覆盖新值.
              if (!box.containsKey(key)) await box.put(key, migrated.toMap());
            })
            .catchError((Object error, StackTrace stackTrace) {
              Log.e('弹幕偏好迁移失败', error: error, stackTrace: stackTrace);
            })
            .whenComplete(() => queue.migrationQueued = false),
      );
    }
    return migrated;
  }

  static Future<void> save(DanmakuPreferences value) {
    final box = GStorage.setting;
    return _queue(box).enqueue(() async {
      final raw = box.get(key);
      if (raw != null && !_supported(raw)) {
        throw StateError('弹幕设置来自不支持的版本, 已保留原数据');
      }
      await box.put(key, value.normalized.toMap());
    });
  }

  static Stream<DanmakuPreferences> watch() => GStorage.setting
      .watch()
      .where(
        (event) =>
            event.key == key ||
            DanmakuPreferencesMigration.legacyKeys.contains(event.key),
      )
      .map((_) => read());

  /// 兼容旧 setter, 界面应使用可等待的 save 接口处理失败.
  static void updateLegacy(
    DanmakuPreferences Function(DanmakuPreferences) update,
  ) {
    final box = GStorage.setting;
    unawaited(
      _queue(box)
          .enqueue(() async {
            final raw = box.get(key);
            if (raw != null && !_supported(raw)) {
              throw StateError('无法覆盖未知版本的弹幕设置');
            }
            final current = raw is Map
                ? DanmakuPreferences.fromMap(raw)
                : DanmakuPreferencesMigration.fromLegacy(box.get);
            await box.put(key, update(current).normalized.toMap());
          })
          .catchError((Object error, StackTrace stackTrace) {
            Log.e('保存弹幕偏好失败', error: error, stackTrace: stackTrace);
          }),
    );
  }
}

class _DanmakuWriteQueue {
  Future<void>? _tail;
  bool migrationQueued = false;

  Future<void> enqueue(Future<void> Function() operation) {
    final previous = _tail;
    final result = previous == null
        ? Future<void>.sync(operation)
        : previous.then((_) => operation());
    final settled = result.catchError((Object _) {});
    _tail = settled;
    unawaited(
      settled.then((_) {
        if (identical(_tail, settled)) _tail = null;
      }),
    );
    return result;
  }
}
