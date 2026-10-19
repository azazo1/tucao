import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

/// 更新包的存放位置.
///
/// 放在 Android 外部应用专属目录下的 updates, 系统安装器通过 FileProvider
/// 才能读到它; 单独一个子目录也让更新包与离线缓存互不干扰.
abstract final class UpdateLocation {
  static Future<Directory> directory({
    Future<Directory?> Function()? externalDirectory,
  }) async {
    final external = await (externalDirectory ?? getExternalStorageDirectory)();
    if (external == null) {
      throw const FileSystemException('应用外部存储不可用, 请检查存储设备');
    }
    return Directory(path.join(external.path, 'updates'));
  }
}
