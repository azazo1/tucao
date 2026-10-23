import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:tucao/models/video.dart';
import 'package:tucao/pages/setting/blocked_page.dart';
import 'package:tucao/services/block_service.dart';

/// 屏蔽测试只使用内存存储, 不访问站点.
class _Box implements Box {
  final data = <dynamic, dynamic>{};
  Future<void> Function()? beforeWrite;
  int writes = 0;

  @override
  dynamic get(dynamic key, {dynamic defaultValue}) => data[key] ?? defaultValue;

  @override
  Future<void> put(dynamic key, dynamic value) async {
    writes++;
    await beforeWrite?.call();
    data[key] = value;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Box box;
  late BlockService service;
  const video = VideoModel(
    hid: '123',
    title: '第一条番剧',
    cover: '',
    typeName: '连载新番',
  );
  const other = VideoModel(
    hid: '456',
    title: '第二条视频',
    cover: '',
    typeName: '综合',
  );

  setUp(() {
    Get.testMode = true;
    box = _Box();
    service = BlockService(box: box);
    service.reload();
    Get.put(service);
  });

  tearDown(() {
    Get.reset();
  });

  test('屏蔽按 hid 去重, 保留展示字段并写入版本号', () async {
    await service.block(video);
    await service.block(other);
    await service.block(
      const VideoModel(hid: '123', title: '更新后的标题', typeName: '连载新番'),
    );
    expect(service.list.map((item) => item.hid), ['123', '456']);
    expect(service.list.first.title, '更新后的标题');
    expect(service.list.first.typeName, '连载新番');
    expect(service.list.first.blockedAt, greaterThan(0));
    expect(box.data[BlockService.storageKey]['version'], 1);

    final restored = BlockService(box: box)..reload();
    expect(restored.list.map((item) => item.hid), ['123', '456']);
    expect(restored.list.first.title, '更新后的标题');
    expect(restored.loadError.value, isNull);
  });

  test('过滤与解除只影响展示, 不改动传入列表', () async {
    await service.block(other);
    final input = [video, other];
    expect(service.isBlocked('456'), isTrue);
    expect(service.isBlocked('123'), isFalse);
    expect(service.isBlocked(''), isFalse);
    expect(service.visibleOf(input).map((item) => item.hid), ['123']);
    expect(input, hasLength(2));

    await service.unblock('456');
    expect(service.isBlocked('456'), isFalse);
    expect(service.visibleOf(input).map((item) => item.hid), ['123', '456']);
  });

  test('未知版本和损坏记录不覆盖原数据', () async {
    for (final raw in [
      {'version': 2, 'items': []},
      {
        'version': 1,
        'items': [
          {'hid': 'bad', 'title': '坏记录'},
        ],
      },
    ]) {
      box.data[BlockService.storageKey] = raw;
      service.reload();
      expect(service.loadError.value, isNotNull);
      await expectLater(service.block(video), throwsStateError);
      expect(identical(box.data[BlockService.storageKey], raw), isTrue);
    }
    expect(box.writes, 0);
  });

  test('写盘失败不发布新状态, 失败后仍可重试', () async {
    box.beforeWrite = () async => throw StateError('disk unavailable');
    await expectLater(service.block(video), throwsStateError);
    expect(service.isBlocked('123'), isFalse);
    box.beforeWrite = null;
    await service.block(video);
    expect(service.isBlocked('123'), isTrue);
  });

  test('并发解除最后以串行写盘结果为准', () async {
    await service.block(video);
    await service.block(other);
    final pending = Completer<void>();
    addTearDown(() {
      if (!pending.isCompleted) {
        pending.complete();
      }
    });
    box.beforeWrite = () => pending.future;
    final first = service.unblock('123');
    final second = service.clear();
    await Future<void>.delayed(Duration.zero);
    expect(service.list.map((item) => item.hid), ['123', '456']);
    pending.complete();
    await Future.wait([first, second]);
    expect(service.list, isEmpty);
    final restored = BlockService(box: box)..reload();
    expect(restored.list, isEmpty);
  });

  testWidgets('屏蔽管理页逐条解除后回到空状态', (tester) async {
    await service.block(video);
    await tester.pumpWidget(const MaterialApp(home: BlockedVideoPage()));
    expect(find.text('第一条番剧'), findsOneWidget);
    await tester.tap(find.byTooltip('解除屏蔽'));
    await tester.pumpAndSettle();
    expect(service.list, isEmpty);
    expect(find.text('还没有屏蔽任何内容'), findsOneWidget);
  });
}
