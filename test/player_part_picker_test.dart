import 'package:canvas_danmaku/canvas_danmaku.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:tucao/models/danmaku.dart';
import 'package:tucao/models/video.dart';
import 'package:tucao/pages/video/widgets/player_view.dart';
import 'package:tucao/plugin/player/player_controller.dart';
import 'package:tucao/plugin/player/tucao_player.dart';
import 'package:tucao/utils/storage.dart';

/// 播放器会读取跳转秒数偏好, 这里用内存替身代替 Hive.
class _Settings implements Box {
  final data = <dynamic, dynamic>{};

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
  @override
  bool get initialized => false;
  @override
  bool get playing => false;
  @override
  bool get completed => false;
  @override
  bool get buffering => false;
  @override
  String? get error => null;
  @override
  Duration get position => Duration.zero;
  @override
  Duration get duration => const Duration(minutes: 2);
  @override
  Duration get buffered => Duration.zero;
  @override
  double get speed => 1;
  @override
  double get volume => 100;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Controller implements PlayerPageController {
  _Controller({int partCount = 1}) {
    video.value = VideoModel(
      hid: '1',
      title: '测试视频',
      parts: [
        for (var index = 0; index < partCount; index++)
          VideoPart(
            title: '第 ${index + 1} 集',
            file: 'http://example.com/${index + 1}.mp4',
          ),
      ],
    );
  }

  /// 切换过的分 P 序号, 用来验证按钮确实调到了控制器.
  final switched = <int>[];

  @override
  final player = _Player();
  @override
  final playerReady = false.obs;
  @override
  final danmakuEnabled = true.obs;
  @override
  final sourceError = RxnString();
  @override
  final part = 0.obs;
  @override
  final video = Rxn<VideoModel>();
  @override
  String get hid => '1';
  @override
  List<VideoPart> get parts => video.value?.parts ?? const [];
  @override
  DanmakuOption get danmakuOption => const DanmakuOption();
  @override
  void attachDanmaku(DanmakuController<DanmakuModel> controller) {}
  @override
  Future<void> togglePlay() async {}
  @override
  Future<void> switchPart(int index) async {
    switched.add(index);
    part.value = index;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 全屏是选集按钮出现的前提, 所以默认按全屏挂载.
Future<void> _mount(
  WidgetTester tester,
  _Controller controller, {
  bool fullscreen = true,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 640,
          height: 360,
          child: VideoPlayerView(
            controller: controller,
            fullscreen: fullscreen,
            onToggleFullscreen: () {},
            onOpenWebsite: () {},
          ),
        ),
      ),
    ),
  );
}

/// 底部弹层自带进场与退场动画, 一次 pump 追不上.
Future<void> _settleSheet(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    GStorage.setting = _Settings();
  });

  tearDown(() {
    Get.reset();
  });

  testWidgets('只有一个分P时全屏也不显示选集按钮', (tester) async {
    final controller = _Controller(partCount: 1);
    await _mount(tester, controller);
    expect(find.byIcon(Icons.playlist_play), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.player.dispose();
  });

  testWidgets('非全屏时不给选集入口', (tester) async {
    final controller = _Controller(partCount: 3);
    await _mount(tester, controller, fullscreen: false);
    expect(find.byIcon(Icons.playlist_play), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.player.dispose();
  });

  testWidgets('全屏多分P时可以选集并切换', (tester) async {
    final controller = _Controller(partCount: 3);
    await _mount(tester, controller);
    final entry = find.byIcon(Icons.playlist_play);
    expect(entry, findsOneWidget);

    await tester.tap(entry);
    await _settleSheet(tester);
    expect(find.text('选集'), findsOneWidget);
    expect(find.byKey(const ValueKey('part-picker-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('part-picker-2')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('part-picker-1')));
    await _settleSheet(tester);
    expect(controller.switched, [1]);
    expect(find.byKey(const ValueKey('part-picker-1')), findsNothing);

    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.player.dispose();
  });

  testWidgets('点当前分P只收起弹层', (tester) async {
    final controller = _Controller(partCount: 2);
    await _mount(tester, controller);
    await tester.tap(find.byIcon(Icons.playlist_play));
    await _settleSheet(tester);

    await tester.tap(find.byKey(const ValueKey('part-picker-0')));
    await _settleSheet(tester);
    expect(controller.switched, isEmpty);
    expect(find.text('选集'), findsNothing);

    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.player.dispose();
  });
}
