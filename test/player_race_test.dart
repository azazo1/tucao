import 'dart:async';

import 'package:canvas_danmaku/canvas_danmaku.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:tucao/models/api_response.dart';
import 'package:tucao/models/danmaku.dart';
import 'package:tucao/models/danmaku_preferences.dart';
import 'package:tucao/models/video.dart';
import 'package:tucao/pages/video/widgets/player_view.dart';
import 'package:tucao/plugin/player/player_controller.dart';
import 'package:tucao/plugin/player/tucao_player.dart';
import 'package:tucao/services/history_service.dart';
import 'package:tucao/utils/storage.dart';

class _Settings implements Box {
  final data = <dynamic, dynamic>{'player_continue_last': false};

  @override
  dynamic get(dynamic key, {dynamic defaultValue}) => data[key] ?? defaultValue;

  @override
  bool containsKey(dynamic key) => data.containsKey(key);

  @override
  Future<void> put(dynamic key, dynamic value) async {
    data[key] = value;
  }

  @override
  Stream<BoxEvent> watch({dynamic key}) => const Stream<BoxEvent>.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Player extends ChangeNotifier implements TucaoPlayer {
  Completer<void>? initialize;
  final opens = <String>[];
  final autoPlays = <bool>[];
  final pausedUrls = <String?>[];
  String? currentUrl;
  bool isPlaying = true;
  int plays = 0;
  Future<void> Function(String)? opening;
  int active = 0;
  int maximumActive = 0;
  int stops = 0;
  bool closed = false;
  String? playbackError;
  Duration currentDuration = Duration.zero;

  @override
  VoidCallback? onCompleted;

  @override
  bool get initialized => false;

  @override
  bool get completed => false;

  @override
  bool get buffering => false;

  @override
  Duration get buffered => Duration.zero;

  @override
  double get speed => 1;

  @override
  double get volume => 100;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  String? get error => playbackError;

  @override
  bool get playing => isPlaying;

  @override
  Duration get duration => currentDuration;

  @override
  Duration get position => Duration.zero;

  @override
  Future<void> init() async => initialize?.future;

  @override
  Future<void> setUrl(
    String url, {
    bool autoPlay = true,
    Duration? startAt,
  }) async {
    opens.add(url);
    autoPlays.add(autoPlay);
    active++;
    if (active > maximumActive) {
      maximumActive = active;
    }
    try {
      await opening?.call(url);
      currentUrl = url;
      isPlaying = autoPlay;
    } finally {
      active--;
    }
  }

  @override
  Future<void> pause() async {
    pausedUrls.add(currentUrl);
    isPlaying = false;
    notifyListeners();
  }

  @override
  Future<void> play() async {
    plays++;
    isPlaying = true;
    notifyListeners();
  }

  @override
  Future<void> toggle() => playing ? pause() : play();

  @override
  Future<void> stop() async => stops++;

  void fail(String? error) {
    playbackError = error;
    notifyListeners();
  }

  @override
  void dispose() {
    closed = true;
    // 不触发 native 或平台插件, 测试仅控制业务边界.
    super.dispose();
  }
}

class _Danmaku implements DanmakuController<DanmakuModel> {
  final delivered = <String>[];
  DanmakuOption? appliedOption;
  int paused = 0;
  int resumed = 0;
  int cleared = 0;

  @override
  ValueChanged<DanmakuOption> get updateOption =>
      (option) => appliedOption = option;

  @override
  ValueChanged<DanmakuContentItem<DanmakuModel>> get addDanmaku =>
      (item) => delivered.add(item.extra!.text);

  @override
  VoidCallback get clear =>
      () => cleared++;

  @override
  VoidCallback get pause =>
      () => paused++;

  @override
  VoidCallback get resume =>
      () => resumed++;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _History extends GetxController implements HistoryService {
  Completer<void>? writing;
  final recorded = <int>[];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<void> record({
    required VideoModel video,
    required int part,
    required double progress,
    required double duration,
  }) async {
    recorded.add(part);
    await writing?.future;
  }
}

const _video = VideoModel(
  hid: '123',
  title: 'race',
  parts: [
    VideoPart(title: 'A', file: 'https://example.invalid/a'),
    VideoPart(title: 'B', file: 'https://example.invalid/b'),
    VideoPart(title: 'C', file: 'https://example.invalid/c'),
    VideoPart(title: 'missing'),
  ],
);

ApiResponse<VideoModel> _response(VideoModel video) =>
    ApiResponse(code: '200', result: video);

DanmakuModel _comment(String text) => DanmakuModel(
  time: 0,
  mode: 1,
  fontSize: 25,
  color: 0xffffff,
  timestamp: 0,
  text: text,
);

Future<void> _flush() async {
  await Future<void>.delayed(Duration.zero);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    GStorage.setting = _Settings();
  });

  tearDown(() {
    Get.reset();
  });

  test('弹幕样式实时生效且暂停时不会因预览恢复播放', () {
    final player = _Player()..isPlaying = false;
    final controller = PlayerPageController(hid: '123', player: player);
    final renderer = _Danmaku();
    controller.attachDanmaku(renderer);
    final pausedBefore = renderer.paused;
    controller.applyDanmakuPreferences(
      DanmakuPreferences.defaults.copyWith(opacity: 0.4, fontSize: 24),
    );
    expect(renderer.appliedOption!.opacity, 0.4);
    expect(renderer.appliedOption!.fontSize, 24);
    expect(renderer.resumed, 0);
    expect(renderer.paused, pausedBefore + 1);
    player.isPlaying = true;
    controller.applyDanmakuPreferences(DanmakuPreferences.defaults);
    expect(renderer.resumed, 1);
    controller.applyDanmakuPreferences(
      DanmakuPreferences.defaults.copyWith(enabled: false),
    );
    expect(controller.danmakuEnabled.value, isFalse);
    expect(renderer.cleared, 1);
    final lastOption = renderer.appliedOption;
    controller.onClose();
    controller.applyDanmakuPreferences(DanmakuPreferences.defaults);
    expect(renderer.appliedOption, same(lastOption));
  });

  test('串行守卫跳过旧排队请求, 单个错误不阻塞新请求', () async {
    final gate = PlayerRequestGate();
    final blocked = Completer<void>();
    final calls = <int>[];
    final first = gate.begin();
    final running = gate.run(first, () async {
      calls.add(first);
      await blocked.future;
      throw StateError('old failure');
    });
    final failure = expectLater(running, throwsStateError);
    await _flush();
    final second = gate.begin();
    final skipped = gate.run(second, () async => calls.add(second));
    final third = gate.begin();
    final latest = gate.run(third, () async => calls.add(third));
    blocked.complete();
    await failure;
    await Future.wait([skipped, latest]);
    expect(calls, [first, third]);
    expect(gate.isCurrent(first), isFalse);
    expect(gate.isCurrent(third), isTrue);
  });

  test('关闭守卫使在途回调失效并丢弃排队工作', () async {
    final gate = PlayerRequestGate();
    final request = gate.begin();
    final blocked = Completer<void>();
    var committed = false;
    var queued = false;
    final running = gate.run(request, () async {
      await blocked.future;
      committed = gate.isCurrent(request);
    });
    await _flush();
    final pending = gate.run(request, () async => queued = true);
    gate.close();
    blocked.complete();
    await Future.wait([running, pending]);
    expect(committed, isFalse);
    expect(queued, isFalse);
  });

  test('连续详情加载只接受最新响应, 旧 finally 不清除新 loading', () async {
    final details = <Completer<ApiResponse<VideoModel>>>[];
    final player = _Player();
    final controller = PlayerPageController(
      hid: '123',
      player: player,
      loadVideo: (_) {
        final request = Completer<ApiResponse<VideoModel>>();
        details.add(request);
        return request.future;
      },
      loadDanmaku: (_, _, _) async => [],
    );
    addTearDown(controller.onClose);
    final old = controller.load();
    final latest = controller.load();
    details[0].complete(_response(const VideoModel(hid: '123', title: 'old')));
    await old;
    expect(controller.firstLoading.value, isTrue);
    expect(controller.video.value, isNull);
    details[1].complete(_response(_video));
    await latest;
    expect(controller.video.value, same(_video));
    expect(controller.firstLoading.value, isFalse);
    expect(player.opens, ['https://example.invalid/a']);
  });

  test('销毁后到达的详情响应不创建播放器或覆盖状态', () async {
    final detail = Completer<ApiResponse<VideoModel>>();
    final player = _Player();
    final controller = PlayerPageController(
      hid: '123',
      player: player,
      loadVideo: (_) => detail.future,
    );
    final load = controller.load();
    controller.onClose();
    detail.complete(_response(_video));
    await load;
    expect(controller.video.value, isNull);
    expect(controller.playerReady.value, isFalse);
    expect(player.opens, isEmpty);
    expect(player.closed, isTrue);
  });

  test('初始化期间快速选分P只打开最后选择', () async {
    final player = _Player()..initialize = Completer<void>();
    final controller = PlayerPageController(
      hid: '123',
      player: player,
      loadVideo: (_) async => _response(_video),
      loadDanmaku: (_, _, _) async => [],
    );
    addTearDown(controller.onClose);
    final initial = controller.load();
    await _flush();
    final second = controller.switchPart(1);
    final latest = controller.switchPart(2);
    await _flush();
    expect(controller.part.value, 2);
    player.initialize!.complete();
    await Future.wait([initial, second, latest]);
    expect(player.opens, ['https://example.invalid/c']);
    expect(controller.playUrl.value, 'https://example.invalid/c');
    expect(player.maximumActive, 1);
  });

  test('open 期间切换保持串行, 旧错误不污染最新请求', () async {
    final opened = Completer<void>();
    final player = _Player()
      ..opening = (url) => url.endsWith('/a') ? opened.future : Future.value();
    final controller = PlayerPageController(
      hid: '123',
      player: player,
      loadVideo: (_) async => _response(_video),
      loadDanmaku: (_, _, _) async => [],
    );
    addTearDown(controller.onClose);
    final initial = controller.load();
    await _flush();
    final second = controller.switchPart(1);
    await _flush();
    final latest = controller.switchPart(2);
    await _flush();
    opened.completeError(StateError('old open failed'));
    await Future.wait([initial, second, latest]);
    expect(player.maximumActive, 1);
    expect(player.opens, [
      'https://example.invalid/a',
      'https://example.invalid/c',
    ]);
    expect(controller.part.value, 2);
    expect(controller.sourceError.value, isNull);
    expect(controller.playUrl.value, 'https://example.invalid/c');
  });

  test('A-B-A 弹幕迟到不能覆盖新的同分P弹幕', () async {
    final comments = <Completer<List<DanmakuModel>>>[];
    final player = _Player();
    final controller = PlayerPageController(
      hid: '123',
      player: player,
      loadVideo: (_) async => _response(_video),
      loadDanmaku: (_, _, _) {
        final request = Completer<List<DanmakuModel>>();
        comments.add(request);
        return request.future;
      },
    );
    addTearDown(controller.onClose);
    final renderer = _Danmaku();
    controller.attachDanmaku(renderer);
    final initial = controller.load();
    await _flush();
    final second = controller.switchPart(1);
    await _flush();
    final latest = controller.switchPart(0);
    await _flush();
    comments[2].complete([_comment('new A')]);
    await latest;
    comments[1].complete([_comment('old B')]);
    comments[0].complete([_comment('old A')]);
    await Future.wait([initial, second]);
    expect(renderer.delivered, ['new A']);
  });

  test('销毁后迟到弹幕不再投递', () async {
    final comments = Completer<List<DanmakuModel>>();
    final player = _Player();
    final controller = PlayerPageController(
      hid: '123',
      player: player,
      loadVideo: (_) async => _response(_video),
      loadDanmaku: (_, _, _) => comments.future,
    );
    final renderer = _Danmaku();
    controller.attachDanmaku(renderer);
    final load = controller.load();
    await _flush();
    controller.onClose();
    comments.complete([_comment('late')]);
    await load;
    expect(renderer.delivered, isEmpty);
  });

  test('历史写入等待期间新选择不被旧切换覆盖, 记录实际播放分P', () async {
    final history = Get.put<HistoryService>(_History()) as _History;
    final player = _Player();
    final controller = PlayerPageController(
      hid: '123',
      player: player,
      loadVideo: (_) async => _response(_video),
      loadDanmaku: (_, _, _) async => [],
    );
    addTearDown(controller.onClose);
    await controller.load();
    player.currentDuration = const Duration(seconds: 60);
    history.writing = Completer<void>();
    final second = controller.switchPart(1);
    final latest = controller.switchPart(2);
    expect(controller.part.value, 2);
    expect(history.recorded, [0, 0]);
    history.writing!.complete();
    await Future.wait([second, latest]);
    expect(player.opens.last, 'https://example.invalid/c');
  });

  test('缺失直链的最后选择等待旧 open 后 stop, 不留下旧播放地址', () async {
    final opened = Completer<void>();
    final player = _Player()..opening = (_) => opened.future;
    final controller = PlayerPageController(
      hid: '123',
      player: player,
      loadVideo: (_) async => _response(_video),
      loadDanmaku: (_, _, _) async => [],
    );
    addTearDown(controller.onClose);
    final initial = controller.load();
    await _flush();
    final missing = controller.switchPart(3);
    await _flush();
    expect(player.stops, 0);
    opened.complete();
    await Future.wait([initial, missing]);
    expect(player.stops, 1);
    expect(controller.playUrl.value, isEmpty);
    expect(controller.sourceError.value, isNotNull);
    expect(controller.playerReady.value, isFalse);
  });

  for (final state in [AppLifecycleState.paused, AppLifecycleState.hidden]) {
    testWidgets('$state 后详情或 init 和弹幕迟到不自动播放, resumed 只允许主动播放', (tester) async {
      (GStorage.setting as _Settings).data['player_background'] = false;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final detail = Completer<ApiResponse<VideoModel>>();
      final initialized = Completer<void>();
      final comments = Completer<List<DanmakuModel>>();
      final player = _Player()..initialize = initialized;
      final controller = PlayerPageController(
        hid: '123',
        player: player,
        loadVideo: (_) => detail.future,
        loadDanmaku: (_, _, _) => comments.future,
      );
      controller.onInit();
      try {
        // hidden 场景先进入 init, paused 场景连详情也在后台才到达.
        if (state == AppLifecycleState.hidden) {
          detail.complete(_response(_video));
          await tester.pump();
        }
        tester.binding.handleAppLifecycleStateChanged(state);
        await tester.pump();
        if (state == AppLifecycleState.paused) {
          detail.complete(_response(_video));
          await tester.pump();
        }
        expect(player.opens, isEmpty);
        initialized.complete();
        await tester.pump();
        expect(player.autoPlays, [false]);
        expect(player.playing, isFalse);
        comments.complete([_comment('late')]);
        await tester.pump();
        expect(controller.firstLoading.value, isFalse);
        expect(player.playing, isFalse);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump();
        expect(player.playing, isFalse);
        expect(player.plays, 0);
        await controller.togglePlay();
        expect(player.playing, isTrue);
        expect(player.plays, 1);
      } finally {
        controller.onClose();
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
      }
    });
  }

  testWidgets('open 期间退后台并换代只暂停旧实际媒体, 不暂停 resumed 后的新媒体', (tester) async {
    (GStorage.setting as _Settings).data['player_background'] = false;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final firstOpened = Completer<void>();
    final nextOpened = Completer<void>();
    final player = _Player()
      ..opening = (url) =>
          url.endsWith('/a') ? firstOpened.future : nextOpened.future;
    final controller = PlayerPageController(
      hid: '123',
      player: player,
      loadVideo: (_) async => _response(_video),
      loadDanmaku: (_, _, _) async => [],
    );
    controller.onInit();
    try {
      await tester.pump();
      expect(player.autoPlays, [true]);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      final next = controller.switchPart(1);
      await tester.pump();
      expect(player.pausedUrls, isEmpty);
      firstOpened.complete();
      await tester.pump();
      expect(player.pausedUrls, ['https://example.invalid/a']);
      expect(player.autoPlays, [true, false]);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      nextOpened.complete();
      await tester.pump();
      await next;
      expect(player.pausedUrls, ['https://example.invalid/a']);
      expect(player.currentUrl, 'https://example.invalid/b');
      expect(player.playing, isFalse);
      expect(player.plays, 0);
      expect(player.maximumActive, 1);
    } finally {
      controller.onClose();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    }
  });

  testWidgets('允许后台播放时迟到详情和 open 保留自动播放策略, 仍尊重 autoPlay 偏好', (tester) async {
    (GStorage.setting as _Settings).data['player_background'] = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final detail = Completer<ApiResponse<VideoModel>>();
    final opened = Completer<void>();
    final player = _Player()
      ..opening = (url) => url.endsWith('/a') ? opened.future : Future.value();
    final controller = PlayerPageController(
      hid: '123',
      player: player,
      loadVideo: (_) => detail.future,
      loadDanmaku: (_, _, _) async => [],
    );
    controller.onInit();
    try {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      detail.complete(_response(_video));
      await tester.pump();
      expect(player.autoPlays, [true]);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      opened.complete();
      await tester.pump();
      expect(player.playing, isTrue);
      expect(player.pausedUrls, isEmpty);
      (GStorage.setting as _Settings).data['player_auto_play'] = false;
      final next = controller.switchPart(1);
      await tester.pump();
      await next;
      expect(player.autoPlays, [true, false]);
      expect(player.playing, isFalse);
      expect(player.pausedUrls, isEmpty);
    } finally {
      controller.onClose();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    }
  });

  testWidgets('播放错误事件显示覆盖层并保留浏览器回调, 全屏返回不受影响', (tester) async {
    final player = _Player();
    final controller = PlayerPageController(hid: '123', player: player);
    controller.playerReady.value = true;
    var opened = 0;
    var fullscreenExited = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 640,
            height: 360,
            child: VideoPlayerView(
              controller: controller,
              fullscreen: true,
              onToggleFullscreen: () => fullscreenExited++,
              onOpenWebsite: () => opened++,
            ),
          ),
        ),
      ),
    );
    expect(find.byIcon(Icons.error_outline), findsNothing);
    player.fail('decoder failed');
    await tester.pump();
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    await tester.tap(find.byIcon(Icons.open_in_browser));
    expect(opened, 1);
    await tester.tap(find.byIcon(Icons.arrow_back));
    expect(fullscreenExited, 1);
    player.fail(null);
    await tester.pump();
    expect(find.byIcon(Icons.error_outline), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.onClose();
  });
}
