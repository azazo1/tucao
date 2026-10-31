import 'package:tucao/models/danmaku_filter.dart';

/// 弹幕屏蔽设置的版本迁移.
///
/// 目前只有第 1 版, 以后改结构时在这里按版本逐级升级.
abstract final class DanmakuFilterMigration {
  /// 把存储里的原始数据升级成当前版本, 无法识别的版本返回 null.
  static DanmakuFilter? migrate(Object? raw) {
    if (raw is! Map) return null;
    final version = raw['version'];
    if (version == DanmakuFilter.version) {
      return DanmakuFilter.fromMap(raw);
    }
    return null;
  }
}
