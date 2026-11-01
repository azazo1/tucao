import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:tucao/models/danmaku.dart';
import 'package:tucao/models/download_task.dart';
import 'package:tucao/models/video.dart';
import 'package:tucao/utils/logger.dart';

/// 缓存媒体之外的附属数据: 视频信息, 封面与各分P弹幕.
///
/// 与任务清单放在同一目录, 但各自成文件, 损坏或缺失只影响离线页的展示,
/// 不影响媒体本身. 每个 json 都带结构版本, 版本不符按缺失处理.
class DownloadExtras {
  DownloadExtras(this.directory);

  static const version = 1;

  final Directory directory;

  File _file(String name) {
    final target = path.normalize(path.join(directory.path, name));
    if (!path.isWithin(directory.path, target) ||
        path.basename(target) != name) {
      throw const FormatException('缓存文件路径越界');
    }
    return File(target);
  }

  static void _checkHid(String hid) {
    if (!DownloadTask.validIdentity(hid, 0)) {
      throw const FormatException('无效的视频编号');
    }
  }

  File info(String hid) {
    _checkHid(hid);
    return _file('$hid.info.json');
  }

  File cover(String hid) {
    _checkHid(hid);
    return _file('$hid.cover');
  }

  File danmaku(DownloadTask task) {
    if (!DownloadTask.validIdentity(task.hid, task.part)) {
      throw const FormatException('无效的缓存任务编号');
    }
    return _file('${task.id}.danmaku.json');
  }

  /// 先写临时文件再改名, 中途失败不会留下半截内容.
  Future<void> _replace(File target, List<int> bytes) async {
    final temporary = File('${target.path}.new');
    await temporary.writeAsBytes(bytes, flush: true);
    await temporary.rename(target.path);
  }

  Future<Object?> _readJson(File file) async {
    if (!await file.exists()) {
      return null;
    }
    final raw = jsonDecode(await file.readAsString());
    if (raw is! Map || raw['version'] != version) {
      throw const FormatException('附属数据结构版本不受支持');
    }
    return raw['data'];
  }

  Future<void> saveVideo(VideoModel video) => _replace(
    info(video.hid),
    utf8.encode(jsonEncode({'version': version, 'data': video.toJson()})),
  );

  Future<VideoModel?> loadVideo(String hid) async {
    try {
      final data = await _readJson(info(hid));
      return data is Map ? VideoModel.fromJson(data.cast()) : null;
    } catch (error) {
      Log.w('读取缓存视频信息失败 $hid: $error');
      return null;
    }
  }

  Future<void> saveCover(String hid, List<int> bytes) =>
      _replace(cover(hid), bytes);

  Future<void> saveDanmaku(DownloadTask task, List<DanmakuModel> items) =>
      _replace(
        danmaku(task),
        utf8.encode(
          jsonEncode({
            'version': version,
            'data': items.map((item) => item.toJson()).toList(),
          }),
        ),
      );

  /// 没有保存过弹幕时返回空, 与 "保存了零条" 区分开.
  Future<List<DanmakuModel>?> loadDanmaku(DownloadTask task) async {
    try {
      final data = await _readJson(danmaku(task));
      if (data is! List) {
        return null;
      }
      return [
        for (final item in data.whereType<Map>())
          DanmakuModel.fromJson(item.cast()),
      ];
    } catch (error) {
      Log.w('读取缓存弹幕失败 ${task.id}: $error');
      return null;
    }
  }

  /// 删掉某个分P的弹幕.
  Future<void> discardPart(DownloadTask task) => _delete(danmaku(task));

  /// 某个视频的分P都删完后, 清掉视频信息与封面.
  Future<void> discardVideo(String hid) async {
    await _delete(info(hid));
    await _delete(cover(hid));
  }

  static Future<void> _delete(File file) async {
    if (await file.exists()) {
      await file.delete();
    }
  }
}
