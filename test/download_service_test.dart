import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:tucao/models/download_task.dart';
import 'package:tucao/models/video.dart';
import 'package:tucao/services/download/download_location.dart';
import 'package:tucao/services/download/download_service.dart';
import 'package:tucao/services/download/download_store.dart';
import 'package:tucao/services/download/download_transport.dart';

class _Request {
  _Request(this.uri, this.file, this.token, this.progress);
  final Uri uri;
  final File file;
  final CancelToken token;
  final void Function(int, int) progress;

  Future<int> complete() async {
    await file.writeAsBytes([1, 2, 3], flush: true);
    progress(3, 3);
    return 3;
  }
}

class _Transport implements DownloadTransport {
  final calls = <_Request>[];
  Future<int> Function(_Request)? behavior;

  @override
  Future<int> fetch({
    required Uri uri,
    required File target,
    required CancelToken cancelToken,
    required void Function(int received, int total) onProgress,
  }) async {
    final request = _Request(uri, target, cancelToken, onProgress);
    calls.add(request);
    return behavior == null ? request.complete() : behavior!(request);
  }
}

class _Store extends DownloadStore {
  _Store(super.directory);

  Future<void> Function(List<DownloadTask>)? beforeSave;
  Future<void> Function()? afterRename;
  Future<void> Function()? beforeDelete;

  @override
  Future<void> save(List<DownloadTask> tasks) async {
    await beforeSave?.call(tasks);
    await super.save(tasks);
  }

  @override
  File media(DownloadTask task, {bool partial = false}) {
    final file = super.media(task, partial: partial);
    final hook = afterRename;
    if (partial && hook != null) {
      return _DelayedRenameFile(file, hook);
    }
    if (!partial && beforeDelete != null) {
      return _DelayedRenameFile(file, () async {}, beforeDelete: beforeDelete);
    }
    return file;
  }
}

class _DelayedRenameFile implements File {
  _DelayedRenameFile(this.file, this.hook, {this.beforeDelete});
  final File file;
  final Future<void> Function() hook;
  final Future<void> Function()? beforeDelete;

  @override
  String get path => file.path;
  @override
  Future<bool> exists() => file.exists();
  @override
  Future<int> length() => file.length();
  @override
  Future<FileSystemEntity> delete({bool recursive = false}) async {
    await beforeDelete?.call();
    return file.delete(recursive: recursive);
  }

  @override
  Future<File> writeAsBytes(
    List<int> bytes, {
    FileMode mode = FileMode.write,
    bool flush = false,
  }) => file.writeAsBytes(bytes, mode: mode, flush: flush);
  @override
  Future<File> rename(String newPath) async {
    final result = await file.rename(newPath);
    await hook();
    return result;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late _Transport transport;
  late DownloadService service;
  const video = VideoModel(
    hid: '123',
    title: '视频标题/不能成为目录',
    parts: [
      VideoPart(title: '第一集', file: 'https://media.example.com/one.mp4'),
      VideoPart(title: '第二集', file: 'https://media.example.com/two.mp4'),
    ],
  );

  setUp(() async {
    final temporary = Directory(
      path.join(Directory.current.path, '.tmp'),
    ).absolute;
    await temporary.create(recursive: true);
    root = await temporary.createTemp('download-service-');
    transport = _Transport();
    service = DownloadService(directory: root, transport: transport);
    await service.initialize();
  });

  tearDown(() async {
    service.onClose();
    await service.waitForIdle();
    final temporary = path.normalize(
      path.join(Directory.current.absolute.path, '.tmp'),
    );
    final target = path.normalize(root.absolute.path);
    expect(path.isWithin(temporary, target), isTrue);
    expect(path.basename(target).startsWith('download-service-'), isTrue);
    await root.delete(recursive: true);
  });

  test('仅使用 Android 外部专属目录, 不可用时不回退内部存储', () async {
    final external = Directory(
      path.join(root.path, 'Android', 'data', 'com.azazo1.tucao', 'files'),
    );
    final directory = await DownloadLocation.directory(
      externalDirectory: () async => external,
    );
    expect(directory.path, path.join(external.path, 'downloads'));
    await expectLater(
      DownloadLocation.directory(externalDirectory: () async => null),
      throwsA(isA<FileSystemException>()),
    );
    var available = false;
    final unavailable = DownloadService(
      transport: transport,
      location: () async {
        if (!available) {
          throw const FileSystemException('外部存储未挂载');
        }
        return directory;
      },
    );
    await expectLater(
      unavailable.initialize(),
      throwsA(isA<FileSystemException>()),
    );
    expect(unavailable.ready.value, isFalse);
    expect(unavailable.initializationError.value, isNotNull);
    available = true;
    await unavailable.initialize();
    expect(unavailable.ready.value, isTrue);
    expect(unavailable.store.directory.path, directory.absolute.path);
    unavailable.onClose();
    await unavailable.waitForIdle();
  });

  test('队列逐个下载, 同视频同分P去重, 完成后只返回真实本地文件', () async {
    final firstStarted = Completer<void>();
    final release = Completer<void>();
    transport.behavior = (request) async {
      if (transport.calls.length == 1) {
        firstStarted.complete();
        await release.future;
      }
      return request.complete();
    };
    await service.enqueue(video, 0);
    await firstStarted.future;
    await service.enqueue(video, 1);
    await service.enqueue(video, 0);
    expect(transport.calls.length, 1);
    expect(service.items.length, 2);
    release.complete();
    await service.waitForIdle();
    expect(
      service.items.every((task) => task.status == DownloadStatus.completed),
      isTrue,
    );
    final file = await service.localFile('123-0');
    expect(await file?.readAsBytes(), [1, 2, 3]);
    expect(file?.path, service.store.media(service.items.first).path);
    expect((await service.store.load()).length, 2);
  });

  test('暂停取消正在写入的请求, 删除半文件, 重试从头下载', () async {
    final started = Completer<void>();
    transport.behavior = (request) async {
      if (transport.calls.length == 1) {
        await request.file.writeAsBytes([1]);
        request.progress(1, 3);
        started.complete();
        throw await request.token.whenCancel;
      }
      return request.complete();
    };
    await service.enqueue(video, 0);
    await started.future;
    await service.pause('123-0');
    await service.waitForIdle();
    final paused = service.find('123-0')!;
    expect(paused.status, DownloadStatus.paused);
    expect(paused.received, 0);
    expect(await service.store.media(paused, partial: true).exists(), isFalse);
    expect(await service.localFile(paused.id), isNull);
    await service.retry(paused.id);
    await service.waitForIdle();
    expect(transport.calls.length, 2);
    expect(service.find(paused.id)?.status, DownloadStatus.completed);
  });

  test('失败清理半文件并保存失败状态, 不当作已缓存', () async {
    transport.behavior = (request) async {
      await request.file.writeAsBytes([1]);
      throw const FormatException('分段媒体不支持');
    };
    await service.enqueue(video, 0);
    await service.waitForIdle();
    final task = service.find('123-0')!;
    expect(task.status, DownloadStatus.failed);
    expect(await service.localFile(task.id), isNull);
    expect(await service.store.media(task, partial: true).exists(), isFalse);
    expect((await service.store.load()).single.status, DownloadStatus.failed);
  });

  test('删除活动任务先取消写入, 任务和文件都不能被迟到回调恢复', () async {
    final started = Completer<void>();
    transport.behavior = (request) async {
      await request.file.writeAsBytes([1]);
      started.complete();
      throw await request.token.whenCancel;
    };
    final task = await service.enqueue(video, 0);
    await started.future;
    await service.remove(task.id);
    await service.waitForIdle();
    expect(service.items, isEmpty);
    expect(await service.store.media(task).exists(), isFalse);
    expect(await service.store.media(task, partial: true).exists(), isFalse);
    expect(await service.store.load(), isEmpty);
  });

  test('恢复任务验证完成文件, 未完成任务暂停且不自动产生流量', () async {
    await service.enqueue(video, 0);
    await service.waitForIdle();
    final completed = service.items.single;
    final pending = DownloadTask(
      hid: '456',
      part: 0,
      title: '另一视频',
      partTitle: '第一集',
      source: 'https://media.example.com/file.mp4',
      createdAt: 1,
      status: DownloadStatus.downloading,
      received: 1,
      total: 3,
    );
    await service.store.media(pending, partial: true).writeAsBytes([1]);
    await service.store.save([completed, pending]);
    final restored = DownloadService(directory: root, transport: transport);
    await restored.initialize();
    expect(restored.find(completed.id)?.status, DownloadStatus.completed);
    expect(restored.find(pending.id)?.status, DownloadStatus.paused);
    expect(
      await restored.store.media(pending, partial: true).exists(),
      isFalse,
    );
    expect(transport.calls.length, 1);
    restored.onClose();
    await restored.waitForIdle();
  });

  test('本地文件缺失后更新为失败, 不返回无效路径', () async {
    await service.enqueue(video, 0);
    await service.waitForIdle();
    final task = service.items.single;
    await service.store.discard(task);
    expect(await service.localFile(task.id), isNull);
    expect(service.find(task.id)?.status, DownloadStatus.failed);
  });

  test('后台暂停活动和排队任务, 返回前台不自动下载', () async {
    final started = Completer<void>();
    transport.behavior = (request) async {
      started.complete();
      throw await request.token.whenCancel;
    };
    await service.enqueue(video, 0);
    await started.future;
    await service.enqueue(video, 1);
    service.didChangeAppLifecycleState(AppLifecycleState.paused);
    await service.waitForIdle();
    service.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await service.waitForIdle();
    expect(transport.calls.length, 1);
    expect(
      service.items.every((task) => task.status == DownloadStatus.paused),
      isTrue,
    );
  });

  test('空直链, HLS 与无效编号在排队前拒绝', () async {
    for (final item in [
      const VideoModel(
        hid: '../bad',
        title: '',
        parts: [VideoPart(title: '', file: 'https://example.com/a.mp4')],
      ),
      const VideoModel(
        hid: '12',
        title: '',
        parts: [VideoPart(title: '', file: 'file:///private/data')],
      ),
      const VideoModel(
        hid: '12',
        title: '',
        parts: [VideoPart(title: '', file: 'https://example.com/a.m3u8')],
      ),
      const VideoModel(
        hid: '12',
        title: '',
        parts: [VideoPart(title: '', vid: 'external')],
      ),
    ]) {
      await expectLater(service.enqueue(item, 0), throwsFormatException);
    }
    expect(service.items, isEmpty);
    expect(transport.calls, isEmpty);
  });

  test('取消尚未收尾时立即重试, 等待旧请求退出后只发起一次新请求', () async {
    final started = Completer<void>();
    final cancelled = Completer<void>();
    final release = Completer<void>();
    final retried = Completer<void>();
    final finishRetry = Completer<void>();
    transport.behavior = (request) async {
      if (transport.calls.length == 1) {
        await request.file.writeAsBytes([1]);
        started.complete();
        final error = await request.token.whenCancel;
        cancelled.complete();
        await release.future;
        throw error;
      }
      retried.complete();
      await finishRetry.future;
      return request.complete();
    };
    await service.enqueue(video, 0);
    await started.future;
    final pausing = service.pause('123-0');
    await cancelled.future;
    final retrying = service.retry('123-0');
    expect(transport.calls.length, 1);
    release.complete();
    await Future.wait([pausing, retrying]);
    await retried.future;
    transport.calls.first.progress(999, 999);
    expect(service.find('123-0')?.received, 0);
    finishRetry.complete();
    await service.waitForIdle();
    expect(transport.calls.length, 2);
    expect(service.find('123-0')?.status, DownloadStatus.completed);
    expect(
      (await service.store.load()).single.status,
      DownloadStatus.completed,
    );
  });

  test('取消发生在最终文件移动期间, 不得覆盖暂停状态或留下已完成文件', () async {
    service.onClose();
    await service.waitForIdle();
    final store = _Store(root);
    service = DownloadService(store: store, transport: transport);
    await service.initialize();
    final moved = Completer<void>();
    final release = Completer<void>();
    store.afterRename = () async {
      moved.complete();
      await release.future;
    };
    final task = await service.enqueue(video, 0);
    await moved.future;
    final pausing = service.pause(task.id);
    release.complete();
    await pausing;
    await service.waitForIdle();
    expect(service.find(task.id)?.status, DownloadStatus.paused);
    expect(await store.media(task).exists(), isFalse);
    expect(await store.media(task, partial: true).exists(), isFalse);
    expect((await store.load()).single.status, DownloadStatus.paused);
  });

  test('排队持久化尚未成功时现有 runner 不得提前启动新任务', () async {
    service.onClose();
    await service.waitForIdle();
    final store = _Store(root);
    service = DownloadService(store: store, transport: transport);
    await service.initialize();
    final completedSaving = Completer<void>();
    final finishSaving = Completer<void>();
    final admissionSaving = Completer<void>();
    final failAdmission = Completer<void>();
    store.beforeSave = (tasks) async {
      if (!completedSaving.isCompleted &&
          tasks.any(
            (task) =>
                task.id == '123-0' && task.status == DownloadStatus.completed,
          )) {
        completedSaving.complete();
        await finishSaving.future;
      } else if (!admissionSaving.isCompleted &&
          tasks.any(
            (task) =>
                task.id == '123-1' && task.status == DownloadStatus.queued,
          )) {
        admissionSaving.complete();
        await failAdmission.future;
        throw const FileSystemException('模拟清单写入失败');
      }
    };
    await service.enqueue(video, 0);
    await completedSaving.future;
    final adding = service.enqueue(video, 1);
    final rejected = expectLater(adding, throwsA(isA<FileSystemException>()));
    finishSaving.complete();
    await admissionSaving.future;
    failAdmission.complete();
    await rejected;
    await service.pauseAll();
    await service.waitForIdle();
    expect(transport.calls.length, 1);
    expect(service.find('123-1')?.status, DownloadStatus.failed);
    expect((await store.load()).last.status, DownloadStatus.failed);
  });

  test('排队保存失败的旧回滚不得覆盖用户已暂停的状态', () async {
    service.onClose();
    await service.waitForIdle();
    final store = _Store(root);
    service = DownloadService(store: store, transport: transport);
    await service.initialize();
    final saving = Completer<void>();
    final release = Completer<void>();
    store.beforeSave = (tasks) async {
      if (!saving.isCompleted && tasks.any((task) => task.id == '123-0')) {
        saving.complete();
        await release.future;
        throw const FileSystemException('模拟清单写入失败');
      }
    };
    final adding = service.enqueue(video, 0);
    final rejected = expectLater(adding, throwsA(isA<FileSystemException>()));
    await saving.future;
    final pausing = service.pause('123-0');
    release.complete();
    await Future.wait([rejected, pausing]);
    await service.waitForIdle();
    expect(service.find('123-0')?.status, DownloadStatus.paused);
    expect(transport.calls, isEmpty);
    expect((await store.load()).single.status, DownloadStatus.paused);
  });

  for (final action in ['complete', 'pause', 'remove']) {
    test('完成保存等待期间不发布本地文件, 保存后遵守 $action 操作', () async {
      service.onClose();
      await service.waitForIdle();
      final store = _Store(root);
      service = DownloadService(store: store, transport: transport);
      await service.initialize();
      final saving = Completer<void>();
      final release = Completer<void>();
      store.beforeSave = (tasks) async {
        if (!saving.isCompleted &&
            tasks.any((task) => task.status == DownloadStatus.completed)) {
          saving.complete();
          await release.future;
        }
      };
      final task = await service.enqueue(video, 0);
      await saving.future;
      expect(service.find(task.id)?.status, DownloadStatus.downloading);
      expect(await service.localFile(task.id), isNull);
      final stopping = action == 'pause'
          ? service.pause(task.id)
          : action == 'remove'
          ? service.remove(task.id)
          : Future<void>.value();
      release.complete();
      await stopping;
      await service.waitForIdle();
      if (action == 'complete') {
        expect(service.find(task.id)?.status, DownloadStatus.completed);
        expect(await service.localFile(task.id), isNotNull);
      } else {
        expect(
          service.find(task.id)?.status,
          action == 'pause' ? DownloadStatus.paused : isNull,
        );
        expect(await store.media(task).exists(), isFalse);
        expect(await service.localFile(task.id), isNull);
      }
    });
  }

  test('最终完成清单写入失败不能暴露未持久化缓存, 后续保存可恢复队列', () async {
    service.onClose();
    await service.waitForIdle();
    final store = _Store(root);
    service = DownloadService(store: store, transport: transport);
    await service.initialize();
    var failed = false;
    final saving = Completer<void>();
    final release = Completer<void>();
    store.beforeSave = (tasks) async {
      if (!failed &&
          tasks.any((task) => task.status == DownloadStatus.completed)) {
        failed = true;
        saving.complete();
        await release.future;
        throw const FileSystemException('模拟完成清单写入失败');
      }
    };
    await service.enqueue(video, 0);
    await saving.future;
    expect(service.find('123-0')?.status, DownloadStatus.downloading);
    expect(await service.localFile('123-0'), isNull);
    release.complete();
    await service.waitForIdle();
    final task = service.find('123-0')!;
    expect(task.status, DownloadStatus.failed);
    expect(await store.media(task).exists(), isFalse);
    expect(await service.localFile(task.id), isNull);
    await service.pauseAll();
    expect((await store.load()).single.status, DownloadStatus.failed);
    await service.retry(task.id);
    await service.waitForIdle();
    expect(service.find(task.id)?.status, DownloadStatus.completed);
  });

  test('删除清单保存失败时保留完成记录和文件, 可再次删除后重新排队', () async {
    service.onClose();
    await service.waitForIdle();
    final store = _Store(root);
    service = DownloadService(store: store, transport: transport);
    await service.initialize();
    await service.enqueue(video, 0);
    await service.waitForIdle();
    final task = service.find('123-0')!;
    store.beforeSave = (_) async {
      throw const FileSystemException('模拟清单写入失败');
    };
    await expectLater(
      service.remove(task.id),
      throwsA(isA<FileSystemException>()),
    );
    expect(service.find(task.id)?.status, DownloadStatus.completed);
    expect(await store.media(task).exists(), isTrue);
    store.beforeSave = null;
    await service.remove(task.id);
    expect(await store.load(), isEmpty);
    await service.enqueue(video, 0);
    await service.waitForIdle();
    expect(transport.calls.length, 2);
    expect(service.find(task.id)?.status, DownloadStatus.completed);
  });

  test('删除文件失败后恢复可管理记录与清单, 再次删除能够清理原文件', () async {
    service.onClose();
    await service.waitForIdle();
    final store = _Store(root);
    service = DownloadService(store: store, transport: transport);
    await service.initialize();
    await service.enqueue(video, 0);
    await service.waitForIdle();
    final task = service.find('123-0')!;
    store.beforeDelete = () async {
      throw const FileSystemException('模拟文件删除失败');
    };
    await expectLater(
      service.remove(task.id),
      throwsA(isA<FileSystemException>()),
    );
    expect(service.find(task.id)?.status, DownloadStatus.completed);
    expect(await store.media(task).exists(), isTrue);
    expect((await store.load()).single.status, DownloadStatus.completed);
    store.beforeDelete = null;
    await service.remove(task.id);
    expect(service.items, isEmpty);
    expect(await store.media(task).exists(), isFalse);
    expect(await store.load(), isEmpty);
  });

  test('主清单截断后从同步备用清单恢复, 保留坏文件且不自动下载', () async {
    await service.enqueue(video, 0);
    await service.waitForIdle();
    final task = service.find('123-0')!;
    await service.store.manifest.writeAsString('{"version":1,"tasks":[');
    final restored = DownloadService(directory: root, transport: transport);
    await restored.initialize();
    expect(restored.find(task.id)?.status, DownloadStatus.completed);
    expect(await restored.localFile(task.id), isNotNull);
    expect(await File(path.join(root.path, 'index.corrupt')).exists(), isTrue);
    expect(transport.calls.length, 1);
    restored.onClose();
    await restored.waitForIdle();
    await service.remove(task.id);
    await service.store.manifest.writeAsString('{');
    expect(await service.store.load(), isEmpty);
  });

  test('清单不能注入路径, 未支持的结构版本不恢复任务', () async {
    final bad = DownloadTask(
      hid: '../escape',
      part: 0,
      title: '',
      partTitle: '',
      source: 'https://example.com/a.mp4',
      createdAt: 1,
    );
    expect(() => service.store.media(bad), throwsFormatException);
    await service.store.save([bad]);
    expect(await service.store.load(), isEmpty);
    await service.store.manifest.writeAsString('{"version":999,"tasks":[]}');
    expect(await service.store.load(), isEmpty);
  });
}
