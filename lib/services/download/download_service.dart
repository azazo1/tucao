import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:tucao/models/download_task.dart';
import 'package:tucao/models/video.dart';
import 'package:tucao/services/download/download_location.dart';
import 'package:tucao/services/download/download_store.dart';
import 'package:tucao/services/download/download_transport.dart';
import 'package:tucao/utils/logger.dart';

/// 前台单文件缓存队列. 不做分段下载, 暂停后重试从头开始.
class DownloadService extends GetxController with WidgetsBindingObserver {
  DownloadService({Directory? directory, required DownloadTransport transport,
    Future<Directory> Function()? location})
    : _store = directory == null ? null : DownloadStore(directory),
      _location = location ?? DownloadLocation.directory,
      _transport = transport;

  static DownloadService get instance => Get.find<DownloadService>();

  DownloadStore? _store;
  DownloadStore get store => _store ?? (throw StateError('外部缓存目录尚未就绪'));
  final Future<Directory> Function() _location;
  final initializationError = RxnString();
  Future<void>? _initializing;
  final DownloadTransport _transport;
  final items = <DownloadTask>[].obs;
  final ready = false.obs;
  Future<void> _saving = Future.value();
  Future<void>? _runner;
  CancelToken? _cancel;
  Completer<void>? _activeFinished;
  String? _activeId;
  bool _foreground = true;
  bool _closed = false;
  final _removing = <String>{};

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    _closed = true;
    _cancel?.cancel('缓存服务已关闭');
    super.onClose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      _foreground = false;
      unawaited(pauseAll().catchError((Object error, StackTrace stackTrace) {
        Log.e('暂停缓存任务失败', error: error, stackTrace: stackTrace);
      }));
    } else if (state == AppLifecycleState.resumed) {
      _foreground = true;
      // 返回应用时不自动产生流量, 由用户主动重试暂停任务.
    }
  }

  Future<void> initialize() {
    if (ready.value) {
      return Future.value();
    }
    return _initializing ??= _initialize().catchError((Object error, StackTrace stackTrace) {
      initializationError.value = '外部缓存目录不可用, 请检查存储设备后重试';
      Log.e('初始化外部缓存目录失败', error: error, stackTrace: stackTrace);
      throw error;
    }).whenComplete(() => _initializing = null);
  }

  Future<void> _initialize() async {
    initializationError.value = null;
    _store ??= DownloadStore(await _location());
    await store.directory.create(recursive: true);
    final saved = await store.load();
    final restored = <DownloadTask>[];
    for (final task in saved) {
      await store.discard(task, partial: true);
      if (task.status == DownloadStatus.completed) {
        final file = store.media(task);
        final valid = await file.exists() && await file.length() > 0 &&
            await file.length() == task.received;
        restored.add(valid ? task : task.update(
          status: DownloadStatus.failed,
          received: 0,
          total: -1,
          error: '本地缓存文件缺失或不完整, 请重新下载',
        ));
      } else {
        restored.add(task.update(
          status: task.status == DownloadStatus.failed ? DownloadStatus.failed : DownloadStatus.paused,
          received: 0,
          total: -1,
          error: task.error,
        ));
      }
    }
    items.assignAll(restored);
    await _persist();
    ready.value = true;
    Log.i('缓存任务恢复完成, 共 ${items.length} 项');
  }

  DownloadTask? find(String id) {
    for (final task in items) {
      if (task.id == id) {
        return task;
      }
    }
    return null;
  }

  void _replace(DownloadTask task) {
    final index = items.indexWhere((item) => item.id == task.id);
    if (index >= 0) {
      items[index] = task;
    }
  }

  Future<void> _persist() {
    final snapshot = items.toList();
    // 写入串行化, 较早的进度快照不能覆盖较晚的任务删除或完成状态.
    _saving = _saving.catchError((Object _) {}).then((_) => store.save(snapshot));
    return _saving;
  }

  Future<DownloadTask> enqueue(VideoModel video, int part) async {
    if (!ready.value || _closed || !_foreground) {
      throw StateError('请等待缓存服务就绪并在应用前台开始下载');
    }
    if (!DownloadTask.validIdentity(video.hid, part) || part >= video.parts.length) {
      throw const FormatException('无效的视频分P');
    }
    final target = video.parts[part];
    final source = target.file?.trim() ?? '';
    final uri = DownloadTask.sourceUri(source);
    if (uri == null) {
      throw const FormatException('该分P没有可下载的直链');
    }
    if (uri.path.toLowerCase().endsWith('.m3u8')) {
      throw const FormatException('暂不支持分段媒体缓存, 请在线播放');
    }
    if (_removing.contains('${video.hid}-$part')) {
      throw StateError('缓存正在删除, 请稍后重试');
    }
    final existing = find('${video.hid}-$part');
    if (existing != null) {
      if (existing.status == DownloadStatus.paused || existing.status == DownloadStatus.failed) {
        // 重新从视频详情添加时使用最新直链, 避免一直重试过期的临时地址.
        _replace(existing.update(source: source));
        await retry(existing.id);
      }
      return find(existing.id)!;
    }
    final task = DownloadTask(
      hid: video.hid,
      part: part,
      title: video.title,
      partTitle: target.title,
      source: source,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    items.add(task);
    try {
      await _persist();
    } catch (error) {
      _replace(task.update(status: DownloadStatus.failed, error: '无法保存缓存任务, 请检查剩余空间'));
      rethrow;
    }
    _schedule();
    return task;
  }

  Future<void> retry(String id) async {
    final task = find(id);
    if (task == null || _removing.contains(id) || _activeId == id ||
        task.status == DownloadStatus.completed ||
        task.status == DownloadStatus.downloading || _closed) {
      return;
    }
    if (!_foreground) {
      throw StateError('请返回应用后再开始缓存');
    }
    _replace(task.update(status: DownloadStatus.queued, received: 0, total: -1));
    try {
      await _persist();
    } catch (error) {
      _replace(task.update(status: DownloadStatus.failed, received: 0, total: -1,
        error: '无法保存缓存任务, 请检查剩余空间'));
      rethrow;
    }
    _schedule();
  }

  Future<void> pause(String id) async {
    final task = find(id);
    if (task == null || ![DownloadStatus.queued, DownloadStatus.downloading].contains(task.status)) {
      return;
    }
    _replace(task.update(status: DownloadStatus.paused, received: 0, total: -1));
    final finished = _activeId == id ? _activeFinished?.future : null;
    if (_activeId == id) {
      _cancel?.cancel('缓存已暂停');
    }
    if (finished != null) {
      await finished;
    }
    await _persist();
  }

  Future<void> pauseAll() async {
    if (!ready.value) {
      return;
    }
    for (final task in items.toList()) {
      if (task.status == DownloadStatus.queued || task.status == DownloadStatus.downloading) {
        _replace(task.update(status: DownloadStatus.paused, received: 0, total: -1));
      }
    }
    final finished = _activeFinished?.future;
    _cancel?.cancel('缓存队列已暂停');
    if (finished != null) {
      await finished;
    }
    await _persist();
  }

  Future<void> remove(String id) async {
    final task = find(id);
    if (task == null || !_removing.add(id)) {
      return;
    }
    try {
      items.removeWhere((item) => item.id == id);
      final finished = _activeId == id ? _activeFinished?.future : null;
      if (_activeId == id) {
        _cancel?.cancel('缓存任务已删除');
      }
      if (finished != null) {
        await finished;
      }
      await store.discard(task, partial: true);
      await store.discard(task);
      await _persist();
      Log.i('已删除缓存任务 ${task.id}');
    } finally {
      _removing.remove(id);
    }
  }

  Future<File?> localFile(String id) async {
    final task = find(id);
    if (task == null || task.status != DownloadStatus.completed) {
      return null;
    }
    final file = store.media(task);
    if (await file.exists() && await file.length() == task.received && task.received > 0) {
      return file;
    }
    _replace(task.update(status: DownloadStatus.failed, error: '本地文件缺失或不完整, 请重新下载'));
    await _persist();
    return null;
  }

  /// 等待当前队列收尾, 用于关闭前或测试. 不会主动开始暂停任务.
  Future<void> waitForIdle() async {
    while (_runner != null) {
      await _runner;
    }
    await _saving;
  }

  void _schedule() {
    if (_runner != null || _closed || !_foreground) {
      return;
    }
    _runner = _run().catchError((Object error, StackTrace stackTrace) {
      Log.e('缓存队列异常', error: error, stackTrace: stackTrace);
    }).whenComplete(() {
      _runner = null;
      if (items.any((task) => task.status == DownloadStatus.queued)) {
        _schedule();
      }
    });
  }

  Future<void> _run() async {
    while (!_closed && _foreground) {
      DownloadTask? next;
      for (final task in items) {
        if (task.status == DownloadStatus.queued) {
          next = task;
          break;
        }
      }
      if (next == null) {
        return;
      }
      final task = next;
      final token = CancelToken();
      final finished = Completer<void>();
      _activeId = task.id;
      _cancel = token;
      _activeFinished = finished;
      _replace(task.update(status: DownloadStatus.downloading));
      final watch = Stopwatch()..start();
      var lastUpdate = -250;
      try {
        await _persist();
        final temporary = store.media(task, partial: true);
        final uri = DownloadTask.sourceUri(task.source);
        if (uri == null) {
          throw const FormatException('无效的缓存来源');
        }
        Log.i('开始缓存任务 ${task.id}');
        final bytes = await _transport.fetch(
          uri: uri,
          target: temporary,
          cancelToken: token,
          onProgress: (received, total) {
            if (watch.elapsedMilliseconds - lastUpdate < 250) {
              return;
            }
            lastUpdate = watch.elapsedMilliseconds;
            final current = find(task.id);
            if (current?.status == DownloadStatus.downloading) {
              _replace(current!.update(received: received, total: total));
            }
          },
        );
        if (token.isCancelled || find(task.id)?.status != DownloadStatus.downloading) {
          throw token.cancelError ?? StateError('缓存任务已停止');
        }
        if (bytes <= 0 || !await temporary.exists() || await temporary.length() != bytes) {
          throw const FormatException('缓存文件为空或不完整');
        }
        // 源路径与目标路径均由已校验的任务编号和私有目录生成.
        await temporary.rename(store.media(task).path);
        _replace(task.update(status: DownloadStatus.completed, received: bytes, total: bytes));
        Log.i('缓存任务 ${task.id} 完成, $bytes 字节, 耗时 ${watch.elapsedMilliseconds}ms');
      } catch (error, stackTrace) {
        final current = find(task.id);
        if (current != null && current.status == DownloadStatus.downloading) {
          _replace(current.update(
            status: token.isCancelled ? DownloadStatus.paused : DownloadStatus.failed,
            received: 0,
            total: -1,
            error: token.isCancelled ? null : _errorText(error),
          ));
        }
        if (!token.isCancelled) {
          Log.e('缓存任务 ${task.id} 失败', error: error, stackTrace: stackTrace);
        }
      } finally {
        try {
          await store.discard(task, partial: true);
          await _persist();
        } finally {
          _activeId = null;
          _cancel = null;
          _activeFinished = null;
          finished.complete();
        }
      }
    }
  }

  String _errorText(Object error) {
    if (error is FormatException) {
      return error.message;
    }
    if (error is FileSystemException) {
      return '无法写入缓存文件, 请检查剩余空间';
    }
    return '下载失败, 请检查网络后重试';
  }
}
