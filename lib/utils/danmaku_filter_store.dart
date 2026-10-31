import 'package:tucao/models/danmaku_filter.dart';
import 'package:tucao/utils/danmaku_filter_migration.dart';
import 'package:tucao/utils/logger.dart';
import 'package:tucao/utils/storage.dart';

/// 弹幕屏蔽设置的读写, 整个设置存成一条 Hive 记录.
abstract final class DanmakuFilterStore {
  static const key = 'danmaku_filter';

  /// 存储里的数据来自更新的版本时为 true, 此时不允许覆盖.
  static bool get hasUnsupportedVersion {
    final raw = GStorage.setting.get(key);
    return raw != null && DanmakuFilterMigration.migrate(raw) == null;
  }

  static DanmakuFilter read() {
    final raw = GStorage.setting.get(key);
    if (raw == null) return DanmakuFilter.defaults;
    final migrated = DanmakuFilterMigration.migrate(raw);
    if (migrated == null) {
      Log.w('弹幕屏蔽设置版本无法识别, 本次使用默认设置');
      return DanmakuFilter.defaults;
    }
    return migrated;
  }

  static Future<void> save(DanmakuFilter value) async {
    if (hasUnsupportedVersion) {
      throw StateError('弹幕屏蔽设置来自不支持的版本, 已保留原数据');
    }
    await GStorage.setting.put(key, value.toMap());
    Log.i(
      '弹幕屏蔽设置已保存, 屏蔽词 ${value.keywords.length} 条, '
      '合并重复 ${value.mergeDuplicates ? '开启' : '关闭'}',
    );
  }

  static Stream<DanmakuFilter> watch() =>
      GStorage.setting.watch(key: key).map((_) => read());
}
