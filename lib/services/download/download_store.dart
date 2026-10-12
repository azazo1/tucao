import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:tucao/models/download_task.dart';
import 'package:tucao/utils/logger.dart';

/// 缓存清单单独带结构版本, 旧版本任务不自动发起网络请求.
class DownloadStore {
  DownloadStore(Directory directory)
    : directory = Directory(path.normalize(directory.absolute.path));

  static const version = 1;
  final Directory directory;

  File _file(String name) {
    final target = path.normalize(path.join(directory.path, name));
    if (!path.isWithin(directory.path, target) || path.basename(target) != name) {
      throw const FormatException('缓存文件路径越界');
    }
    return File(target);
  }

  File get manifest => _file('index.json');

  /// 路径在删除或移动前均重新核对, 不读取清单中提供的文件路径.
  File media(DownloadTask task, {bool partial = false}) {
    if (!DownloadTask.validIdentity(task.hid, task.part)) {
      throw const FormatException('无效的缓存任务编号');
    }
    return _file('${task.id}.${partial ? 'part' : 'media'}');
  }

  Future<List<DownloadTask>> load() async {
    if (!await manifest.exists()) {
      return [];
    }
    try {
      final raw = jsonDecode(await manifest.readAsString());
      if (raw is! Map || raw['version'] != version || raw['tasks'] is! List) {
        Log.w('缓存清单结构不受支持, 未自动恢复任务');
        return [];
      }
      final tasks = <DownloadTask>[];
      final ids = <String>{};
      for (final entry in raw['tasks'] as List) {
        try {
          final task = DownloadTask.fromJson((entry as Map).cast<String, dynamic>());
          if (ids.add(task.id)) {
            tasks.add(task);
          }
        } catch (error) {
          Log.w('忽略无效的缓存任务: $error');
        }
      }
      return tasks;
    } catch (error, stackTrace) {
      Log.e('读取缓存清单失败', error: error, stackTrace: stackTrace);
      return [];
    }
  }

  Future<void> save(List<DownloadTask> tasks) async {
    final temporary = _file('index.new');
    await temporary.writeAsString(jsonEncode({
      'version': version,
      'tasks': tasks.map((task) => task.toJson()).toList(),
    }), flush: true);
    // 两个目标都由固定目录和固定文件名得到, 未采用外部传入路径.
    await temporary.rename(manifest.path);
  }

  Future<void> discard(DownloadTask task, {bool partial = false}) async {
    final target = media(task, partial: partial);
    if (await target.exists()) {
      await target.delete();
    }
  }
}
