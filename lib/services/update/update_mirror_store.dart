import 'dart:convert';

import 'package:tucao/models/update_mirror.dart';
import 'package:tucao/utils/logger.dart';
import 'package:tucao/utils/storage_pref.dart';

/// 镜像源配置的存储与迁移.
///
/// 配置以 json 存在偏好里, 自带结构版本号. 配置读不懂时一律回落到内置
/// 默认源, 避免坏数据把下载入口堵死; 但用户主动清空列表是允许的,
/// 这时按"没有启用的镜像"处理, 由下载源设置决定后续行为.
abstract final class UpdateMirrorStore {
  /// 当前配置结构版本, 结构变化时递增并在 [read] 里补迁移.
  static const version = 1;

  /// 读取全部镜像源, 顺序即下载时的尝试顺序.
  static List<UpdateMirror> read() {
    final raw = Pref.updateMirrors;
    if (raw.isEmpty) {
      return List.of(UpdateMirror.builtin);
    }
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (error) {
      Log.w('更新镜像源配置已损坏, 使用内置默认源: $error');
      return List.of(UpdateMirror.builtin);
    }
    if (decoded is! Map) {
      Log.w('更新镜像源配置结构不符, 使用内置默认源');
      return List.of(UpdateMirror.builtin);
    }
    if (decoded['version'] != version) {
      // 目前只有第一版结构, 读到别的版本说明配置来自更新或更旧的程序,
      // 先回落到默认源, 等结构变更时在这里按版本逐级升级.
      Log.w('更新镜像源配置版本为 ${decoded['version']}, 使用内置默认源');
      return List.of(UpdateMirror.builtin);
    }
    final list = decoded['mirrors'];
    if (list is! List) {
      return List.of(UpdateMirror.builtin);
    }
    final mirrors = <UpdateMirror>[];
    for (final entry in list) {
      final mirror = UpdateMirror.fromJson(entry);
      if (mirror == null) {
        continue;
      }
      // 同一个前缀只留一条, 免得下载时对同一个站重复请求.
      if (mirrors.any((item) => item.prefix == mirror.prefix)) {
        continue;
      }
      mirrors.add(mirror);
    }
    return mirrors;
  }

  /// 覆盖保存整份配置.
  static void write(List<UpdateMirror> mirrors) {
    Pref.updateMirrors = jsonEncode({
      'version': version,
      'mirrors': [for (final mirror in mirrors) mirror.toJson()],
    });
  }

  /// 参与下载的镜像前缀, 按配置顺序.
  static List<String> enabledPrefixes() => [
    for (final mirror in read())
      if (mirror.enabled) mirror.prefix,
  ];

  /// 至少启用了一个镜像源.
  static bool get hasEnabled => read().any((mirror) => mirror.enabled);

  /// 恢复内置默认源.
  static void restoreDefaults() => write(List.of(UpdateMirror.builtin));
}
