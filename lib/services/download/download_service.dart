import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:tucao/models/danmaku.dart';
import 'package:tucao/models/download_task.dart';
import 'package:tucao/models/video.dart';
import 'package:tucao/services/download/download_assets.dart';
import 'package:tucao/services/download/download_extras.dart';
import 'package:tucao/services/download/download_location.dart';
import 'package:tucao/services/download/download_store.dart';
import 'package:tucao/services/download/download_transport.dart';
import 'package:tucao/utils/logger.dart';

/// 正在下载的一个任务.
class _Transfer {
  final cancel = CancelToken();
  final finished = Completer<void>();
}

/// 前台单文件缓存队列, 按加入顺序同时下载 [concurrency] 个任务.
///
/// 暂停与失败保留 `.part` 分片, 重试时按 Range 续传, 服务端不支持时从头下载.
/// 单个任务按 [connections] 分段并发, 见 [DownloadTransport.fetch].
/// 媒体之外顺带保存视频信息, 封面与弹幕, 见 [DownloadExtras].
class DownloadService extends GetxController with WidgetsBindingObserver {
  DownloadService({
    Directory? directory,
    DownloadStore? store,
    required DownloadTransport transport,
    DownloadAssets? assets,
    Future<Directory> Function()? location,
    int Function()? concurrency,
    int Function()? connections,
  }) : assert(directory == null || store == null),
       _store = store ?? (directory == null ? null : DownloadStore(directory)),
       _location = location ?? DownloadLocation.directory,
       _transport = transport,
       _assets = assets,
       _concurrency = concurrency ?? (() => 1),
       _connections = connections ?? (() => 1);

  static DownloadService get instance => Get.find<DownloadService>();

  DownloadStore? _store;
  DownloadStore get store => _store ?? (throw StateError('外部缓存目录尚未就绪'));

  /// 为空表示不保存附属数据, 只缓存媒体.
  final DownloadAssets? _assets;

  DownloadExtras? _extras;
  DownloadExtras get extras => _extras ??= DownloadExtras(store.directory);

  /// 正在下载的任务网速, 字节每秒.
  final speeds = <String, int>{}.obs;

  /// 已经保存了封面的视频.
  final covers = <String>{}.obs;

  /// 已保存的视频信息, 列表展示作者等字段时用, 不必逐行读文件.
  final videos = <String, VideoModel>{}.obs;

  /// 各任务在途的附属数据保存, 删除前要等它们写完.
  final _assetJobs = <String, Future<void>>{};
  final Future<Directory> Function() _location;
  final initializationError = RxnString();
  Future<void>? _initializing;
  final DownloadTransport _transport;

  /// 同时下载的任务数, 每次排队时重新读取, 调整设置后不用重启.
  final int Function() _concurrency;

  /// 单个任务的分段连接数, 只影响之后开始的下载.
  final int Function() _connections;
  final items = <DownloadTask>[].obs;
  final ready = false.obs;
  Future<void> _saving = Future.value();

  /// 正在下载的任务, 键是任务编号.
  final _active = <String, _Transfer>{};
  bool _foreground = true;
  bool _closed = false;
  final _removing = <String>{};
  final _pending = <String>{};

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    _closed = true;
    for (final transfer in _active.values) {
      transfer.cancel.cancel('缓存服务已关闭');
    }
    super.onClose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _foreground = false;
      unawaited(
        pauseAll().catchError((Object error, StackTrace stackTrace) {
          Log.e('暂停缓存任务失败', error: error, stackTrace: stackTrace);
        }),
      );
    } else if (state == AppLifecycleState.resumed) {
      _foreground = true;
      // 返回应用时不自动产生流量, 由用户主动重试暂停任务.
    }
  }

  Future<void> initialize() {
    if (ready.value) {
      return Future.value();
    }
    return _initializing ??= _initialize()
        .catchError((Object error, StackTrace stackTrace) {
          initializationError.value = '外部缓存目录不可用, 请检查存储设备后重试';
          Log.e('初始化外部缓存目录失败', error: error, stackTrace: stackTrace);
          throw error;
        })
        .whenComplete(() => _initializing = null);
  }

  Future<void> _initialize() async {
    initializationError.value = null;
    _store ??= DownloadStore(await _location());
    await store.directory.create(recursive: true);
    final saved = await store.load();
    final restored = <DownloadTask>[];
    for (final task in saved) {
      if (task.status != DownloadStatus.completed) {
        // 保留分片供续传, 进度以磁盘上实际写下的字节为准.
        final kept = await store.partialProgress(task);
        restored.add(
          task.update(
            status: task.status == DownloadStatus.failed
                ? DownloadStatus.failed
                : DownloadStatus.paused,
            received: kept.received,
            total: kept.total,
            error: task.error,
          ),
        );
        continue;
      }
      await store.discard(task, partial: true);
      final file = store.media(task);
      final valid =
          await file.exists() &&
          await file.length() > 0 &&
          await file.length() == task.received;
      restored.add(
        valid
            ? task
            : task.update(
                status: DownloadStatus.failed,
                received: 0,
                total: -1,
                error: '本地缓存文件缺失或不完整, 请重新下载',
              ),
      );
    }
    items.assignAll(restored);
    await _persist();
    final withCover = <String>{};
    final infos = <String, VideoModel>{};
    for (final hid in restored.map((task) => task.hid).toSet()) {
      if (await extras.cover(hid).exists()) {
        withCover.add(hid);
      }
      if (await extras.loadVideo(hid) case final video?) {
        infos[hid] = video;
      }
    }
    covers.assignAll(withCover);
    videos.assignAll(infos);
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

  Future<void> _persist({DownloadTask? completed}) {
    final snapshot = items
        .map((task) => task.id == completed?.id ? completed! : task)
        .toList();
    // 写入串行化, 较早的进度快照不能覆盖较晚的任务删除或完成状态.
    _saving = _saving
        .catchError((Object _) {})
        .then((_) => store.save(snapshot));
    return _saving;
  }

  Future<DownloadTask> enqueue(VideoModel video, int part) async {
    if (!ready.value || _closed || !_foreground) {
      throw StateError('请等待缓存服务就绪并在应用前台开始下载');
    }
    if (!DownloadTask.validIdentity(video.hid, part) ||
        part >= video.parts.length) {
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
      if (existing.status == DownloadStatus.paused ||
          existing.status == DownloadStatus.failed) {
        // 重新从视频详情添加时使用最新直链, 避免一直重试过期的临时地址.
        _replace(existing.update(source: source));
        _trackExtras(existing, () => _saveExtras(video, existing));
        await retry(existing.id);
      }
      final current = find(existing.id);
      if (current == null || _removing.contains(existing.id)) {
        throw StateError('缓存任务已删除');
      }
      return current;
    }
    final task = DownloadTask(
      hid: video.hid,
      part: part,
      title: video.title,
      partTitle: target.title,
      source: source,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    _pending.add(task.id);
    items.add(task);
    try {
      await _persist();
    } catch (error) {
      if (identical(find(task.id), task)) {
        _replace(
          task.update(
            status: DownloadStatus.failed,
            error: '无法保存缓存任务, 请检查剩余空间',
          ),
        );
      }
      rethrow;
    } finally {
      _pending.remove(task.id);
    }
    _trackExtras(task, () => _saveExtras(video, task));
    _schedule();
    return find(task.id) ?? (throw StateError('缓存任务已删除'));
  }

  /// 记下在途的附属数据保存, 同一任务的后一次排在前一次之后.
  void _trackExtras(DownloadTask task, Future<void> Function() job) {
    if (_assets == null) {
      return;
    }
    final previous = _assetJobs[task.id] ?? Future.value();
    late final Future<void> current;
    current = previous.catchError((Object _) {}).then((_) => job()).whenComplete(() {
      if (identical(_assetJobs[task.id], current)) {
        _assetJobs.remove(task.id);
      }
    });
    _assetJobs[task.id] = current;
  }

  /// 保存视频信息, 封面与该分P弹幕. 失败只记日志, 不影响媒体下载.
  Future<void> _saveExtras(VideoModel video, DownloadTask task) async {
    final assets = _assets;
    if (assets == null || _closed) {
      return;
    }
    try {
      await _storeVideo(video);
    } catch (error, stackTrace) {
      Log.e('保存缓存视频信息失败 ${video.hid}', error: error, stackTrace: stackTrace);
    }
    if (!covers.contains(video.hid)) {
      try {
        final bytes = await assets.cover(video);
        if (bytes != null && _stillCached(task)) {
          await extras.saveCover(video.hid, bytes);
          covers.add(video.hid);
        }
      } catch (error) {
        Log.w('保存缓存封面失败 ${video.hid}: $error');
      }
    }
    try {
      final danmaku = await assets.danmaku(video, task.part);
      if (_stillCached(task)) {
        await extras.saveDanmaku(task, danmaku);
        Log.i('已保存缓存弹幕 ${task.id}, 共 ${danmaku.length} 条');
      }
    } catch (error) {
      Log.w('保存缓存弹幕失败 ${task.id}: $error');
    }
  }

  /// 保存视频信息并同步内存表.
  ///
  /// 详情接口的简介是截断的, 已存的简介更长时保留旧的.
  /// 分P地址存的是线上直链, 离线播放时由 [offlineVideo] 换成本地文件.
  Future<VideoModel> _storeVideo(VideoModel video) async {
    final saved = videos[video.hid] ?? await extras.loadVideo(video.hid);
    final merged =
        saved != null && saved.description.length > video.description.length
        ? video.copyWith(description: saved.description)
        : video;
    await extras.saveVideo(merged);
    videos[video.hid] = merged;
    return merged;
  }

  /// 任务还在列表里且没有被删除, 附属数据才值得写.
  bool _stillCached(DownloadTask task) =>
      !_closed && !_removing.contains(task.id) && find(task.id) != null;

  /// 重新拉取视频信息, 封面与已缓存分P的弹幕.
  ///
  /// 老版本缓存没有附属数据, 也可以用它补上. 返回成功更新弹幕的分P数.
  Future<int> refreshExtras(String hid) async {
    final assets = _assets;
    if (assets == null || !ready.value) {
      return 0;
    }
    final tasks = items.where((task) => task.hid == hid).toList();
    if (tasks.isEmpty) {
      return 0;
    }
    final fetched = await assets.video(hid);
    final merged = fetched == null
        ? await extras.loadVideo(hid)
        : await _storeVideo(fetched);
    if (merged == null) {
      throw StateError('视频信息拉取失败');
    }
    covers.remove(hid);
    var updated = 0;
    for (final task in tasks) {
      final job = Completer<bool>();
      _trackExtras(task, () async {
        try {
          if (!covers.contains(hid)) {
            final bytes = await assets.cover(merged);
            if (bytes != null && _stillCached(task)) {
              await extras.saveCover(hid, bytes);
              covers.add(hid);
            }
          }
        } catch (error) {
          Log.w('更新缓存封面失败 $hid: $error');
        }
        try {
          final danmaku = await assets.danmaku(merged, task.part);
          if (_stillCached(task)) {
            await extras.saveDanmaku(task, danmaku);
          }
          job.complete(true);
        } catch (error) {
          Log.w('更新缓存弹幕失败 ${task.id}: $error');
          job.complete(false);
        }
      });
      if (await job.future) {
        updated++;
      }
    }
    // 封面可能没换, 补回标记, 让列表继续显示本地图.
    if (!covers.contains(hid) && await extras.cover(hid).exists()) {
      covers.add(hid);
    }
    Log.i('已更新缓存附属数据 $hid, 弹幕 $updated/${tasks.length}');
    return updated;
  }

  /// 已保存的视频信息, 老版本缓存或保存失败时为空.
  Future<VideoModel?> savedVideo(String hid) => extras.loadVideo(hid);

  /// 已保存的封面文件, 没有时为空.
  File? coverFile(String hid) =>
      covers.contains(hid) ? extras.cover(hid) : null;

  /// 已保存的分P弹幕, 没有保存过时为空.
  Future<List<DanmakuModel>?> savedDanmaku(String id) async {
    final task = find(id);
    return task == null ? null : extras.loadDanmaku(task);
  }

  /// 离线播放用的视频信息: 已缓存分P指向本地文件, 其余分P没有地址.
  ///
  /// 没有保存视频信息的老缓存按任务里的标题拼一份.
  Future<VideoModel?> offlineVideo(String hid) async {
    final tasks = {
      for (final task in items)
        if (task.hid == hid) task.part: task,
    };
    if (tasks.isEmpty) {
      return null;
    }
    final saved = await extras.loadVideo(hid);
    final maxPart = tasks.keys.reduce((a, b) => a > b ? a : b);
    final count = saved == null || saved.parts.length <= maxPart
        ? maxPart + 1
        : saved.parts.length;
    final parts = <VideoPart>[];
    for (var index = 0; index < count; index++) {
      final base = saved != null && index < saved.parts.length
          ? saved.parts[index]
          : VideoPart(title: tasks[index]?.partTitle ?? '');
      final task = tasks[index];
      String? file;
      if (task != null && task.status == DownloadStatus.completed) {
        file = (await localFile(task.id))?.uri.toString();
      }
      parts.add(base.withFile(file));
    }
    final first = tasks.values.first;
    final video = saved ?? VideoModel(hid: hid, title: first.title);
    return video.copyWith(parts: parts);
  }

  Future<void> retry(String id) async {
    var task = find(id);
    if (task == null ||
        _removing.contains(id) ||
        _pending.contains(id) ||
        !ready.value ||
        _closed ||
        ![DownloadStatus.paused, DownloadStatus.failed].contains(task.status)) {
      return;
    }
    if (!_foreground) {
      throw StateError('请返回应用后再开始缓存');
    }
    // 取消后的旧请求必须先完成文件清理, 不能丢弃用户的立即重试.
    if (_active[id] case final transfer?) {
      await transfer.finished.future;
      if (!identical(find(id), task) || _removing.contains(id) || _closed) {
        return;
      }
      if (!_foreground) {
        throw StateError('请返回应用后再开始缓存');
      }
    }
    // 保留已有进度, 实际续传起点由 _run 按分片长度重新核对.
    final queued = (find(id) ?? task).update(status: DownloadStatus.queued);
    _pending.add(id);
    _replace(queued);
    try {
      await _persist();
    } catch (error) {
      if (identical(find(id), queued)) {
        _replace(
          queued.update(
            status: DownloadStatus.failed,
            error: '无法保存缓存任务, 请检查剩余空间',
          ),
        );
      }
      rethrow;
    } finally {
      _pending.remove(id);
    }
    _schedule();
  }

  Future<void> pause(String id) async {
    final task = find(id);
    if (task == null ||
        ![
          DownloadStatus.queued,
          DownloadStatus.downloading,
        ].contains(task.status)) {
      return;
    }
    _replace(task.update(status: DownloadStatus.paused));
    speeds.remove(id);
    if (_active[id] case final transfer?) {
      transfer.cancel.cancel('缓存已暂停');
      await transfer.finished.future;
    }
    await _persist();
  }

  Future<void> pauseAll() async {
    if (!ready.value) {
      return;
    }
    for (final task in items.toList()) {
      if (task.status == DownloadStatus.queued ||
          task.status == DownloadStatus.downloading) {
        _replace(task.update(status: DownloadStatus.paused));
      }
    }
    speeds.clear();
    final running = _active.values.toList();
    for (final transfer in running) {
      transfer.cancel.cancel('缓存队列已暂停');
    }
    await Future.wait(running.map((transfer) => transfer.finished.future));
    await _persist();
  }

  /// 继续所有暂停与失败的任务, 按加入顺序排队.
  Future<void> resumeAll() async {
    for (final task in items.toList()) {
      if (task.status == DownloadStatus.paused ||
          task.status == DownloadStatus.failed) {
        await retry(task.id);
      }
    }
  }

  Future<void> remove(String id) async {
    final task = find(id);
    if (task == null || !_removing.add(id)) {
      return;
    }
    try {
      if (task.status == DownloadStatus.downloading ||
          task.status == DownloadStatus.queued) {
        _replace(task.update(status: DownloadStatus.paused));
      }
      speeds.remove(id);
      if (_active[id] case final transfer?) {
        transfer.cancel.cancel('缓存任务已删除');
        await transfer.finished.future;
      }
      items.removeWhere((item) => item.id == id);
      // 先持久化删除, 写入失败时不能丢失仍在磁盘上的缓存记录.
      try {
        await _persist();
      } catch (_) {
        items.add(
          task.status == DownloadStatus.completed
              ? task
              : task.update(
                  status: DownloadStatus.paused,
                  received: 0,
                  total: -1,
                ),
        );
        rethrow;
      }
      try {
        await store.discard(task, partial: true);
        await store.discard(task);
      } catch (error, stackTrace) {
        var restored = task.update(
          status: DownloadStatus.failed,
          received: 0,
          total: -1,
          error: '无法删除缓存文件, 请检查存储设备后重试',
        );
        if (task.status == DownloadStatus.completed) {
          try {
            final file = store.media(task);
            if (await file.exists() && await file.length() == task.received) {
              restored = task;
            }
          } on FileSystemException {
            // 删除途中存储设备可能已不可用, 仍保留可再次删除的记录.
          }
        }
        items.add(restored);
        try {
          await _persist();
        } catch (saveError, saveStackTrace) {
          Log.e('恢复删除失败的缓存记录失败', error: saveError, stackTrace: saveStackTrace);
        }
        Error.throwWithStackTrace(error, stackTrace);
      }
      await _discardExtras(task);
      Log.i('已删除缓存任务 ${task.id}');
    } finally {
      _removing.remove(id);
    }
  }

  /// 媒体删完后再清附属数据, 失败只留下无主的小文件, 不回滚删除.
  Future<void> _discardExtras(DownloadTask task) async {
    try {
      await _assetJobs[task.id];
      await extras.discardPart(task);
      if (!items.any((item) => item.hid == task.hid)) {
        await extras.discardVideo(task.hid);
        covers.remove(task.hid);
        videos.remove(task.hid);
      }
    } catch (error, stackTrace) {
      Log.e('清理缓存附属数据失败 ${task.id}', error: error, stackTrace: stackTrace);
    }
  }

  Future<File?> localFile(String id) async {
    final task = find(id);
    if (task == null || task.status != DownloadStatus.completed) {
      return null;
    }
    final file = store.media(task);
    var valid = false;
    try {
      valid =
          await file.exists() &&
          await file.length() == task.received &&
          task.received > 0;
    } on FileSystemException {
      // 文件可能在 exists 与 length 之间被并发删除.
    }
    if (!identical(find(id), task) || _removing.contains(id)) {
      return null;
    }
    if (valid) {
      return file;
    }
    _replace(
      task.update(status: DownloadStatus.failed, error: '本地文件缺失或不完整, 请重新下载'),
    );
    await _persist();
    return null;
  }

  /// 等待当前队列收尾, 用于关闭前或测试. 不会主动开始暂停任务.
  Future<void> waitForIdle() async {
    while (_active.isNotEmpty || _assetJobs.isNotEmpty) {
      await Future.wait(
        _active.values.map((transfer) => transfer.finished.future).toList(),
      );
      await Future.wait(_assetJobs.values.toList());
    }
    await _saving;
  }

  /// 同时缓存数调大后立即补上空位; 调小时不打断已在下载的任务.
  void reschedule() => _schedule();

  /// 按加入顺序补满空位.
  void _schedule() {
    if (_closed || !_foreground) {
      return;
    }
    var limit = _concurrency();
    if (limit < 1) {
      limit = 1;
    }
    for (final task in items.toList()) {
      if (_active.length >= limit) {
        return;
      }
      if (task.status == DownloadStatus.queued &&
          !_pending.contains(task.id) &&
          !_active.containsKey(task.id)) {
        _start(task);
      }
    }
  }

  void _start(DownloadTask task) {
    final transfer = _Transfer();
    _active[task.id] = transfer;
    _replace(task.update(status: DownloadStatus.downloading));
    unawaited(
      _download(task, transfer.cancel)
          .catchError((Object error, StackTrace stackTrace) {
            Log.e('缓存队列异常', error: error, stackTrace: stackTrace);
          })
          .whenComplete(() {
            _active.remove(task.id);
            // 先补上空位再通知等待者, waitForIdle 不会在两步之间误判空闲.
            _schedule();
            transfer.finished.complete();
          }),
    );
  }

  Future<void> _download(DownloadTask task, CancelToken token) async {
    final watch = Stopwatch()..start();
    var lastUpdate = -250;
    var published = false;
    var invalid = false;
    void checkActive() {
      if (token.isCancelled ||
          find(task.id)?.status != DownloadStatus.downloading) {
        throw token.cancelError ?? StateError('缓存任务已停止');
      }
    }

    try {
      await _persist();
      checkActive();
      final temporary = store.media(task, partial: true);
      final uri = DownloadTask.sourceUri(task.source);
      if (uri == null) {
        throw const FormatException('无效的缓存来源');
      }
      // 以磁盘上已写下的字节为准, 超出记录总长说明分片不可信.
      final kept = await store.partialProgress(task);
      var offset = kept.received;
      var known = kept.total;
      if (task.total >= 0 && offset > task.total) {
        offset = 0;
        known = -1;
      }
      final active = find(task.id);
      if (active != null && active.status == DownloadStatus.downloading) {
        _replace(active.update(received: offset, total: offset > 0 ? known : -1));
      }
      final connections = _connections();
      Log.i(
        offset > 0
            ? '续传缓存任务 ${task.id}, 已有 $offset 字节'
            : '开始缓存任务 ${task.id}, 连接数 $connections',
      );
      var sampleAt = 0;
      var sampleBytes = offset;
      var speed = 0.0;
      final bytes = await _transport.fetch(
        uri: uri,
        target: temporary,
        cancelToken: token,
        offset: offset,
        expectedTotal: offset > 0 ? task.total : -1,
        connections: connections,
        onProgress: (received, total) {
          final now = watch.elapsedMilliseconds;
          if (now - lastUpdate < 250) {
            return;
          }
          lastUpdate = now;
          final current = find(task.id);
          if (!token.isCancelled &&
              identical(_active[task.id]?.cancel, token) &&
              current?.status == DownloadStatus.downloading) {
            _replace(current!.update(received: received, total: total));
            // 每秒左右取一次样, 平滑后显示, 避免数字来回跳.
            final elapsed = now - sampleAt;
            if (elapsed >= 1000) {
              final instant = (received - sampleBytes) * 1000 / elapsed;
              speed = speed == 0 ? instant : speed * 0.6 + instant * 0.4;
              speeds[task.id] = speed.round().clamp(0, 1 << 40);
              sampleAt = now;
              sampleBytes = received;
            }
          }
        },
      );
      checkActive();
      if (bytes <= 0 ||
          !await temporary.exists() ||
          await temporary.length() != bytes) {
        throw const FormatException('缓存文件为空或不完整');
      }
      checkActive();
      // 源路径与目标路径均由已校验的任务编号和私有目录生成.
      await temporary.rename(store.media(task).path);
      published = true;
      checkActive();
      final completed = task.update(
        status: DownloadStatus.completed,
        received: bytes,
        total: bytes,
      );
      // 完成快照落盘前不暴露本地文件, 保存期间仍允许取消.
      await _persist(completed: completed);
      checkActive();
      _replace(completed);
      Log.i(
        '缓存任务 ${task.id} 完成, $bytes 字节, 耗时 ${watch.elapsedMilliseconds}ms',
      );
    } catch (error, stackTrace) {
      // 内容校验失败说明分片里不是媒体, 不能拿来续传.
      invalid = !token.isCancelled && error is FormatException;
      final current = find(task.id);
      if (current != null && current.status == DownloadStatus.downloading) {
        _replace(
          current.update(
            status: token.isCancelled
                ? DownloadStatus.paused
                : DownloadStatus.failed,
            received: invalid ? 0 : null,
            total: invalid ? -1 : null,
            error: token.isCancelled ? null : _errorText(error),
          ),
        );
      }
      if (!token.isCancelled) {
        Log.e('缓存任务 ${task.id} 失败', error: error, stackTrace: stackTrace);
      }
    } finally {
      speeds.remove(task.id);
      // 暂停与网络失败保留分片, 删除由 remove 负责清理.
      if (invalid || find(task.id) == null) {
        await store.discard(task, partial: true);
      }
      final after = find(task.id);
      if (published && after?.status != DownloadStatus.completed) {
        await store.discard(task);
        // 分片已经提交后又被丢弃, 下次只能从头下载.
        if (after != null) {
          _replace(after.update(received: 0, total: -1, error: after.error));
        }
      }
      try {
        await _persist();
      } catch (_) {
        final current = find(task.id);
        if (current?.status == DownloadStatus.completed) {
          _replace(
            current!.update(
              status: DownloadStatus.failed,
              received: 0,
              total: -1,
              error: '无法保存缓存任务, 请检查剩余空间',
            ),
          );
          await store.discard(task);
        }
        rethrow;
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
    if (error is DownloadInterruptedException) {
      return '连接中断, 可继续下载';
    }
    return '下载失败, 请检查网络后重试';
  }
}
