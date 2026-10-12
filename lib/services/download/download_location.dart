import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

/// Android 外部应用专属目录, 不退回 /data/data 内部存储.
abstract final class DownloadLocation {
  static Future<Directory> directory({
    Future<Directory?> Function()? externalDirectory,
  }) async {
    final external = await (externalDirectory ?? getExternalStorageDirectory)();
    if (external == null) {
      throw const FileSystemException('应用外部存储不可用, 请检查存储设备');
    }
    return Directory(path.join(external.path, 'downloads'));
  }
}
