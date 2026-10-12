import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:tucao/http/favorite_http.dart';
import 'package:tucao/models/favorite.dart';
import 'package:tucao/models/video.dart';
import 'package:tucao/pages/favorite/favorite_page.dart';
import 'package:tucao/pages/favorite/widgets/favorite_button.dart';
import 'package:tucao/services/favorite_service.dart';
import 'package:tucao/utils/http_util.dart';

/// 收藏测试只使用内存存储和 fakeAdapter, 不访问站点.
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

class _Adapter implements HttpClientAdapter {
  String response = '{"status":1}';
  int status = 200;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(response, status);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Box box;
  late FavoriteService service;
  const video = VideoModel(
    hid: '123',
    title: '第一条',
    typeId: 11,
    typeName: '连载新番',
    userId: 42,
    userName: '作者',
    description: '简介',
    partCount: 3,
  );
  const other = VideoModel(hid: '456', title: '第二条', typeId: 11);

  setUp(() {
    Get.testMode = true;
    box = _Box();
    service = FavoriteService(box: box);
    service.reload();
  });

  tearDown(() {
    Get.reset();
  });

  test('新增按 hid 去重, 最新记录置顶, 持久化可恢复且不覆盖历史', () async {
    box.data['history'] = ['existing-history'];
    await service.add(video);
    await service.add(other);
    await service.add(const VideoModel(hid: '123', title: '更新标题', typeId: 11));
    expect(service.list.map((item) => item.video.hid), ['123', '456']);
    final restored = FavoriteService(box: box)..reload();
    expect(restored.list.map((item) => item.video.hid), ['123', '456']);
    expect(restored.list.first.video.title, '更新标题');
    expect(box.data[FavoriteService.storageKey]['version'], 1);
    expect(box.data['history'], ['existing-history']);
  });

  test('元信息序列化不丢分区, 投稿人和分 P 数量', () {
    final item = FavoriteItem(video: video, savedAt: 99);
    final decoded = FavoriteItem.fromJson(item.toJson());
    expect(decoded.savedAt, 99);
    expect(decoded.video.hid, video.hid);
    expect(decoded.video.typeId, 11);
    expect(decoded.video.userId, 42);
    expect(decoded.video.userName, video.userName);
    expect(decoded.video.description, video.description);
    expect(decoded.video.partCount, 3);
  });

  test('写盘成功之前不发布新状态, 失败不假成功且后续可重试', () async {
    final pending = Completer<void>();
    addTearDown(() {
      if (!pending.isCompleted) {
        pending.complete();
      }
    });
    box.beforeWrite = () => pending.future;
    final added = service.add(video);
    await Future<void>.delayed(Duration.zero);
    expect(service.list, isEmpty);
    pending.complete();
    await added;
    expect(service.contains('123'), isTrue);
    box.beforeWrite = () async => throw StateError('disk unavailable');
    await expectLater(service.remove('123'), throwsStateError);
    expect(service.contains('123'), isTrue);
    box.beforeWrite = null;
    await service.remove('123');
    expect(service.list, isEmpty);
  });

  test('并发变更串行执行, 不把较早写盘结果覆盖最新状态', () async {
    final first = service.add(video);
    final second = service.add(other);
    final third = service.remove(video.hid);
    await Future.wait([first, second, third]);
    expect(service.list.map((item) => item.video.hid), ['456']);
    final restored = FavoriteService(box: box)..reload();
    expect(restored.list.map((item) => item.video.hid), ['456']);
    expect(await service.toggle(other), isFalse);
    expect(await service.toggle(video), isTrue);
  });

  test('未知版本和损坏记录不覆盖原数据', () async {
    for (final raw in [
      {'version': 2, 'items': []},
      {
        'version': 1,
        'items': [
          {'savedAt': 1, 'video': {}},
        ],
      },
    ]) {
      box.data[FavoriteService.storageKey] = raw;
      service.reload();
      expect(service.loadError.value, isNotNull);
      await expectLater(service.add(video), throwsStateError);
      expect(identical(box.data[FavoriteService.storageKey], raw), isTrue);
    }
    expect(box.writes, 0);
  });

  testWidgets('详情按钮无需登录, 取消需确认, 保存等待期间禁止重复操作', (tester) async {
    service = FavoriteService(box: box)..reload();
    Get.put(service);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: FavoriteButton(video: video)),
      ),
    );
    final toggle = find.byKey(const ValueKey('favorite-toggle'));
    expect(tester.getSize(toggle).width, lessThanOrEqualTo(48));
    expect(tester.widget<IconButton>(toggle).isSelected, isFalse);
    await tester.tap(toggle);
    await tester.pump();
    expect(box.writes, 1, reason: '首次收藏必须进入内存写盘适配器');
    await tester.pumpAndSettle();
    expect(service.contains('123'), isTrue);
    expect(tester.widget<IconButton>(toggle).isSelected, isTrue);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.tap(find.byKey(const ValueKey('favorite-cancel')));
    await tester.pumpAndSettle();
    expect(service.contains('123'), isTrue);
    final pending = Completer<void>();
    addTearDown(() {
      if (!pending.isCompleted) {
        pending.complete();
      }
    });
    box.beforeWrite = () => pending.future;
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('favorite-confirm')));
    await tester.pump(const Duration(milliseconds: 350));
    expect(box.writes, 2, reason: '取消确认后必须进入第二次持久化');
    expect(service.contains('123'), isTrue);
    expect(tester.widget<IconButton>(toggle).onPressed, isNull);
    pending.complete();
    await tester.pumpAndSettle();
    expect(service.contains('123'), isFalse);
  });

  testWidgets('收藏页复用列表卡片, 删除确认后才移除条目', (tester) async {
    service = FavoriteService(box: box)..reload();
    Get.put(service);
    await service.add(video);
    await tester.pumpWidget(const MaterialApp(home: FavoritePage()));
    final row = find.byKey(const ValueKey('favorite-123'));
    expect(row, findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('favorite-remove-123')));
    await tester.pumpAndSettle();
    expect(row, findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.tap(find.byKey(const ValueKey('favorite-confirm')));
    await tester.pumpAndSettle();
    expect(row, findsNothing);
    expect(service.list, isEmpty);
  });

  for (final page in [false, true]) {
    testWidgets('覆盖路由后迟到的取消确认不删除记录, page=$page', (tester) async {
      service = FavoriteService(box: box)..reload();
      Get.put(service);
      await service.add(video);
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          home: page
              ? const FavoritePage()
              : Scaffold(body: FavoriteButton(video: video)),
        ),
      );
      await tester.tap(
        find.byKey(ValueKey(page ? 'favorite-remove-123' : 'favorite-toggle')),
      );
      await tester.pumpAndSettle();
      final writes = box.writes;
      navigator.currentState!.pop(true);
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: SizedBox.expand()),
        ),
      );
      await tester.pumpAndSettle();
      expect(service.contains('123'), isTrue);
      expect(box.writes, writes);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('覆盖路由后迟到的写盘失败不提示新页面, page=$page', (tester) async {
      service = FavoriteService(box: box)..reload();
      Get.put(service);
      if (page) {
        await service.add(video);
      }
      final pending = Completer<void>();
      addTearDown(() {
        if (!pending.isCompleted) {
          pending.complete();
        }
      });
      box.beforeWrite = () => pending.future;
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          home: page
              ? const FavoritePage()
              : Scaffold(body: FavoriteButton(video: video)),
        ),
      );
      await tester.tap(
        find.byKey(ValueKey(page ? 'favorite-remove-123' : 'favorite-toggle')),
      );
      if (page) {
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('favorite-confirm')));
      }
      await tester.pump(const Duration(milliseconds: 350));
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: SizedBox.expand()),
        ),
      );
      await tester.pump(const Duration(milliseconds: 350));
      pending.completeError(StateError('disk unavailable'));
      await tester.pumpAndSettle();
      expect(service.contains('123'), page);
      expect(find.byType(SnackBar), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  group('独立官网新增收藏契约, 不接本地 UI', () {
    const onlineVideo = VideoModel(
      hid: '123',
      title: 'HTTP fixture',
      typeId: 24,
      userId: 42,
    );
    late _Adapter adapter;
    setUpAll(() {
      HttpUtil.init();
    });
    setUp(() {
      adapter = _Adapter();
      HttpUtil.dio.httpClientAdapter = adapter;
    });

    test('字段与官网一致, 收藏 id 是数字 hid 而非评论复合 id', () async {
      await FavoriteHttp.add(video: onlineVideo);
      final request = adapter.requests.single;
      expect(request.method, 'GET');
      expect(request.uri.path, '/api.php');
      expect(request.queryParameters['op'], 'add_favorite');
      expect(request.queryParameters['contentid'], '123');
      expect(request.queryParameters['modelid'], 11);
      expect(request.queryParameters['ccatid'], 24);
      expect(request.queryParameters['url'], '/play/h123/');
      expect(request.queryParameters['cuserid'], 42);
    });

    test('空响应, HTML, 负状态和 HTTP 错误不能当成成功', () async {
      for (final raw in ['', '<body>success</body>', '{"status":-1}', '{}']) {
        adapter.response = raw;
        await expectLater(
          FavoriteHttp.add(video: onlineVideo),
          throwsStateError,
        );
      }
      adapter.response = '{"status":1}';
      adapter.status = 403;
      await expectLater(
        FavoriteHttp.add(video: onlineVideo),
        throwsA(isA<DioException>()),
      );
      expect(FavoriteHttp.isSuccess('({"status":1})'), isTrue);
    });
  });
}
