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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late _Transport transport;
  late DownloadService service;
  const video = VideoModel(hid: '123', title: '视频标题/不能成为目录', parts: [
    VideoPart(title: '第一集', file: 'https://media.example.com/one.mp4'),
    VideoPart(title: '第二集', file: 'https://media.example.com/two.mp4'),
  ]);

  setUp(() async {
    final temporary = Directory(path.join(Directory.current.path, '.tmp')).absolute;
    await temporary.create(recursive: true);
    root = await temporary.createTemp('download-service-');
    transport = _Transport();
    service = DownloadService(directory: root, transport: transport);
    await service.initialize();
  });

  tearDown(() async {
    service.onClose();
    await service.waitForIdle();
    final temporary = path.normalize(path.join(Directory.current.absolute.path, '.tmp'));
    final target = path.normalize(root.absolute.path);
    expect(path.isWithin(temporary, target), isTrue);
    expect(path.basename(target).startsWith('download-service-'), isTrue);
    await root.delete(recursive: true);
  });

  test('仅使用 Android 外部专属目录, 不可用时不回退内部存储', () async {
    final external = Directory(path.join(root.path, 'Android', 'data', 'com.azazo1.tucao', 'files'));
    final directory = await DownloadLocation.directory(externalDirectory: () async => external);
    expect(directory.path, path.join(external.path, 'downloads'));
    await expectLater(DownloadLocation.directory(externalDirectory: () async => null),
      throwsA(isA<FileSystemException>()));
    var available = false;
    final unavailable = DownloadService(transport: transport, location: () async {
      if (!available) {
        throw const FileSystemException('外部存储未挂载');
      }
      return directory;
    });
    await expectLater(unavailable.initialize(), throwsA(isA<FileSystemException>()));
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
    expect(service.items.every((task) => task.status == DownloadStatus.completed), isTrue);
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
      hid: '456', part: 0, title: '另一视频', partTitle: '第一集',
      source: 'https://media.example.com/file.mp4', createdAt: 1,
      status: DownloadStatus.downloading, received: 1, total: 3,
    );
    await service.store.media(pending, partial: true).writeAsBytes([1]);
    await service.store.save([completed, pending]);
    final restored = DownloadService(directory: root, transport: transport);
    await restored.initialize();
    expect(restored.find(completed.id)?.status, DownloadStatus.completed);
    expect(restored.find(pending.id)?.status, DownloadStatus.paused);
    expect(await restored.store.media(pending, partial: true).exists(), isFalse);
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
    expect(service.items.every((task) => task.status == DownloadStatus.paused), isTrue);
  });

  test('空直链, HLS 与无效编号在排队前拒绝', () async {
    for (final item in [
      const VideoModel(hid: '../bad', title: '', parts: [VideoPart(title: '', file: 'https://example.com/a.mp4')]),
      const VideoModel(hid: '12', title: '', parts: [VideoPart(title: '', file: 'file:///private/data')]),
      const VideoModel(hid: '12', title: '', parts: [VideoPart(title: '', file: 'https://example.com/a.m3u8')]),
      const VideoModel(hid: '12', title: '', parts: [VideoPart(title: '', vid: 'external')]),
    ]) {
      await expectLater(service.enqueue(item, 0), throwsFormatException);
    }
    expect(service.items, isEmpty);
    expect(transport.calls, isEmpty);
  });

  test('清单不能注入路径, 未支持的结构版本不恢复任务', () async {
    final bad = DownloadTask(hid: '../escape', part: 0, title: '', partTitle: '',
      source: 'https://example.com/a.mp4', createdAt: 1);
    expect(() => service.store.media(bad), throwsFormatException);
    await service.store.save([bad]);
    expect(await service.store.load(), isEmpty);
    await service.store.manifest.writeAsString('{"version":999,"tasks":[]}');
    expect(await service.store.load(), isEmpty);
  });
}
