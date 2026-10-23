import 'package:hive_ce_flutter/hive_flutter.dart';

/// Hive 存储盒名称.
abstract final class BoxName {
  static const setting = 'setting';
  static const account = 'account';
  static const history = 'history';
  static const searchHistory = 'search_history';
  static const cookie = 'cookie';
  static const blocked = 'blocked';
}

/// 本地存储入口.
///
/// 存储内容带版本号, 版本不匹配时由 [migration] 处理升级.
abstract final class GStorage {
  /// 当前存储结构版本, 结构变更时递增并补充迁移逻辑.
  static const int version = 1;

  static const String _versionKey = 'storage_version';

  /// 存储盒是否已经打开, 供按需创建的服务判断可用性.
  static bool initialized = false;

  static late Box setting;
  static late Box account;
  static late Box history;
  static late Box searchHistory;
  static late Box blocked;

  static Future<void> init() async {
    await Hive.initFlutter();
    setting = await Hive.openBox(BoxName.setting);
    account = await Hive.openBox(BoxName.account);
    history = await Hive.openBox(BoxName.history);
    searchHistory = await Hive.openBox(BoxName.searchHistory);
    blocked = await Hive.openBox(BoxName.blocked);
    await migration();
    initialized = true;
  }

  /// 旧版本数据的迁移入口.
  static Future<void> migration() async {
    final current = setting.get(_versionKey) as int?;
    if (current == version) {
      return;
    }
    if (current == null) {
      // 首次安装, 直接写入版本号.
      await setting.put(_versionKey, version);
      return;
    }
    // 后续结构变更在这里按版本号顺序补齐.
    await setting.put(_versionKey, version);
  }
}
