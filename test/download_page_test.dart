import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:tucao/models/download_task.dart';
import 'package:tucao/models/video.dart';
import 'package:tucao/pages/download/cached_video_page.dart';
import 'package:tucao/pages/download/download_page.dart';
import 'package:tucao/pages/video/widgets/download_sheet.dart';
import 'package:tucao/services/download/download_service.dart';

/// 完全覆写页面所用服务, 不初始化文件目录, 网络或播放器.
class _FakeDownloads extends GetxController implements DownloadService {
  @override
  final items = <DownloadTask>[].obs;
  @override
  final ready = true.obs;
  @override
  final initializationError = RxnString();

  final pauses = <String>[];
  final retries = <String>[];
  final removals = <String>[];
  final submissions = <int>[];
  final lookups = <String>[];
  int initializations = 0;
  Completer<void>? action;
  Completer<File?>? lookup;
  Future<DownloadTask> Function(VideoModel, int)? submit;

  @override
  Future<void> initialize() async {
    initializations++;
    if (action != null) await action!.future;
    ready.value = true;
  }

  @override
  Future<void> pause(String id) async {
    pauses.add(id);
    if (action != null) await action!.future;
  }

  @override
  Future<void> retry(String id) async {
    retries.add(id);
    if (action != null) await action!.future;
  }

  @override
  Future<void> remove(String id) async {
    removals.add(id);
    if (action != null) await action!.future;
    items.removeWhere((task) => task.id == id);
  }

  @override
  Future<File?> localFile(String id) async {
    lookups.add(id);
    return lookup == null ? null : await lookup!.future;
  }

  @override
  Future<DownloadTask> enqueue(VideoModel video, int part) async {
    submissions.add(part);
    if (submit != null) return await submit!(video, part);
    return _task(part, DownloadStatus.queued);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

DownloadTask _task(
  int part,
  DownloadStatus status, {
  int received = 0,
  int total = -1,
}) => DownloadTask(
  hid: '123',
  part: part,
  title: '离线测试',
  partTitle: '分 P',
  source: 'https://media.example.com/test.mp4',
  createdAt: 1,
  status: status,
  received: received,
  total: total,
);

Finder _key(String key) => find.byKey(ValueKey(key));

void main() {
  late _FakeDownloads service;

  setUp(() {
    Get.testMode = true;
    service = _FakeDownloads();
    Get.put<DownloadService>(service);
  });
  tearDown(() {
    Get.reset();
  });

  Future<void> page(WidgetTester tester) async {
    await tester.pumpWidget(const GetMaterialApp(home: DownloadPage()));
    await tester.pump();
  }

  Future<void> sheet(WidgetTester tester, VideoModel video, int part) async {
    tester.view.physicalSize = const Size(800, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => IconButton(
              icon: const Icon(Icons.download),
              onPressed: () => showVideoDownloadSheet(
                context,
                video: video,
                initialPart: part,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byIcon(Icons.download));
    await tester.pumpAndSettle();
  }

  testWidgets('进度使用任务实际字节比例, 未知长度不伪造比例, 已缓存单独分组', (tester) async {
    service.items.assignAll([
      _task(0, DownloadStatus.downloading, received: 32, total: 128),
      _task(1, DownloadStatus.downloading, received: 9),
      _task(2, DownloadStatus.completed, received: 128, total: 128),
    ]);
    await page(tester);
    final known = tester.widget<LinearProgressIndicator>(
      find.descendant(
        of: _key('123-0'),
        matching: find.byType(LinearProgressIndicator),
      ),
    );
    final unknown = tester.widget<LinearProgressIndicator>(
      find.descendant(
        of: _key('123-1'),
        matching: find.byType(LinearProgressIndicator),
      ),
    );
    expect(known.value, 0.25);
    expect(unknown.value, isNull);
    expect(_key('123-2'), findsNothing);
    await tester.tap(find.byType(Tab).at(1));
    final controller = DefaultTabController.of(
      tester.element(find.byType(TabBar)),
    );
    expect(controller.index, 1);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(_key('123-2'), findsOneWidget);
    expect(_key('download-action-123-2'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('任务操作防重, 页面销毁后异步完成不触发 setState', (tester) async {
    service.items.assignAll([_task(0, DownloadStatus.downloading)]);
    service.action = Completer<void>();
    await page(tester);
    await tester.tap(_key('download-action-123-0'));
    await tester.pump();
    expect(service.pauses, ['123-0']);
    expect(
      tester.widget<TextButton>(_key('download-action-123-0')).onPressed,
      isNull,
    );
    expect(
      tester.widget<IconButton>(_key('download-remove-123-0')).onPressed,
      isNull,
    );
    await tester.tap(_key('download-action-123-0'));
    expect(service.pauses.length, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    service.action!.complete();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('暂停任务重试与删除确认, 删除未完成前保持操作锁', (tester) async {
    service.items.assignAll([_task(0, DownloadStatus.paused)]);
    await page(tester);
    await tester.tap(_key('download-action-123-0'));
    await tester.pump();
    expect(service.retries, ['123-0']);
    expect(service.pauses, isEmpty);
    await tester.tap(_key('download-remove-123-0'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(service.removals, isEmpty);
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextButton),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(service.removals, isEmpty);
    service.action = Completer<void>();
    await tester.tap(_key('download-remove-123-0'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(FilledButton),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(service.removals, ['123-0']);
    expect(service.items.length, 1);
    expect(
      tester.widget<IconButton>(_key('download-remove-123-0')).onPressed,
      isNull,
    );
    service.action!.complete();
    await tester.pump();
    expect(service.items, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('已缓存先查本地文件, 返回空文件不进入播放器', (tester) async {
    service.items.assignAll([
      _task(0, DownloadStatus.completed, received: 1, total: 1),
    ]);
    service.lookup = Completer<File?>();
    await page(tester);
    await tester.tap(find.byType(Tab).at(1));
    final controller = DefaultTabController.of(
      tester.element(find.byType(TabBar)),
    );
    expect(controller.index, 1);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    await tester.tap(_key('123-0'));
    await tester.pump();
    expect(service.lookups, ['123-0']);
    expect(find.byType(CachedVideoPage), findsNothing);
    service.lookup!.complete(null);
    await tester.pump();
    expect(find.byType(CachedVideoPage), findsNothing);
    expect(find.byType(SnackBar), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('服务未就绪只提供初始化重试, 不访问外部目录', (tester) async {
    service.ready.value = false;
    service.initializationError.value = 'fake-storage-unavailable';
    service.action = Completer<void>();
    await page(tester);
    await tester.tap(_key('download-initialize'));
    await tester.pump();
    expect(service.initializations, 1);
    expect(
      tester.widget<FilledButton>(_key('download-initialize')).onPressed,
      isNull,
    );
    service.action!.complete();
    await tester.pump();
    expect(service.ready.value, isTrue);
    expect(_key('download-initialize'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('非法媒体与重复任务禁选, 暂停任务允许选择重试, 初始选择仅限可用分 P', (tester) async {
    const video = VideoModel(
      hid: '123',
      title: '选择测试',
      parts: [
        VideoPart(title: '缺少地址'),
        VideoPart(title: '非法地址', file: 'file:///unavailable.mp4'),
        VideoPart(
          title: '分段媒体',
          file: 'https://example.com/a.M3U8?token=sample',
        ),
        VideoPart(title: '队列', file: 'https://example.com/queue.mp4'),
        VideoPart(title: '完成', file: 'https://example.com/done.mp4'),
        VideoPart(title: '暂停', file: 'https://example.com/paused.mp4'),
      ],
    );
    service.items.assignAll([
      _task(3, DownloadStatus.queued),
      _task(4, DownloadStatus.completed),
      _task(5, DownloadStatus.paused),
    ]);
    await sheet(tester, video, 2);
    for (var part = 0; part < 5; part++) {
      final checkbox = tester.widget<CheckboxListTile>(
        _key('download-part-$part'),
      );
      expect(checkbox.onChanged, isNull);
      expect(checkbox.value, isFalse);
    }
    expect(
      tester.widget<FilledButton>(_key('download-submit')).onPressed,
      isNull,
    );
    final available = tester.widget<CheckboxListTile>(_key('download-part-5'));
    expect(available.onChanged, isNotNull);
    await tester.tap(_key('download-part-5'));
    await tester.pump();
    await tester.tap(_key('download-submit'));
    await tester.pumpAndSettle();
    expect(service.submissions, [5]);
    expect(find.byType(CheckboxListTile), findsNothing);
    expect(find.byType(SnackBar), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('多分 P 串行提交, 失败不阻断后续, 弹层销毁后不继续提交', (tester) async {
    const video = VideoModel(
      hid: '123',
      title: '串行测试',
      parts: [
        VideoPart(title: '一', file: 'https://example.com/one.mp4'),
        VideoPart(title: '二', file: 'https://example.com/two.mp4'),
        VideoPart(title: '三', file: 'https://example.com/three.mp4'),
      ],
    );
    final first = Completer<DownloadTask>();
    service.submit = (video, part) async {
      if (part == 0) return await first.future;
      if (part == 1) throw StateError('fake failure');
      return _task(part, DownloadStatus.queued);
    };
    await sheet(tester, video, 0);
    expect(
      tester.widget<CheckboxListTile>(_key('download-part-0')).value,
      isTrue,
    );
    for (final part in [1, 2]) {
      await tester.tap(_key('download-part-$part'));
      await tester.pump();
    }
    await tester.tap(_key('download-submit'));
    await tester.pump();
    expect(service.submissions, [0]);
    expect(
      tester.widget<FilledButton>(_key('download-submit')).onPressed,
      isNull,
    );
    first.complete(_task(0, DownloadStatus.queued));
    await tester.pumpAndSettle();
    expect(service.submissions, [0, 1, 2]);
    expect(find.byType(SnackBar), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());

    service.submissions.clear();
    final pending = Completer<DownloadTask>();
    service.submit = (video, part) => pending.future;
    await sheet(tester, video, 0);
    await tester.tap(_key('download-part-1'));
    await tester.pump();
    await tester.tap(_key('download-submit'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    pending.complete(_task(0, DownloadStatus.queued));
    await tester.pump();
    expect(service.submissions, [0]);
    expect(tester.takeException(), isNull);
  });
}
