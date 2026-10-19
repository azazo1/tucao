import 'package:canvas_danmaku/canvas_danmaku.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:tucao/models/danmaku.dart';
import 'package:tucao/models/video.dart';
import 'package:tucao/pages/video/widgets/player_gesture.dart';
import 'package:tucao/pages/video/widgets/player_view.dart';
import 'package:tucao/plugin/player/player_controller.dart';
import 'package:tucao/plugin/player/tucao_player.dart';
import 'package:tucao/utils/storage.dart';
import 'package:tucao/utils/storage_pref.dart';

/// 只保存键值的 Hive 替身, 用来验证偏好读写.
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
  Duration currentPosition = const Duration(minutes: 5);
  Duration currentDuration = const Duration(minutes: 20);
  final seeks = <Duration>[];

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
  Duration get position => currentPosition;
  @override
  Duration get duration => currentDuration;
  @override
  Duration get buffered => Duration.zero;
  @override
  double get speed => 1;
  @override
  double get volume => 100;
  @override
  Future<void> seek(Duration position) async => seeks.add(position);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Controller implements PlayerPageController {
  @override
  final _Player player = _Player();
  @override
  final playerReady = false.obs;
  @override
  final danmakuEnabled = true.obs;
  @override
  final sourceError = RxnString();
  @override
  final part = 0.obs;
  // 控制条上的选集按钮要读分P列表, 这里让它没有分P可选.
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
  Future<void> seek(Duration position) async => player.seek(position);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _mount(
  WidgetTester tester,
  _Controller controller, {
  bool fullscreen = false,
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    GStorage.setting = _Settings();
  });

  tearDown(() {
    Get.reset();
  });

  group('跳转秒数偏好', () {
    test('默认 90 秒', () {
      expect(Pref.playerSeekStep, 90.0);
    });

    test('超出区间的旧值被收敛到区间内', () {
      GStorage.setting.put('player_seek_step', 300.0);
      expect(Pref.playerSeekStep, Pref.playerSeekStepMax);
      GStorage.setting.put('player_seek_step', 10.0);
      expect(Pref.playerSeekStep, Pref.playerSeekStepMin);
    });

    test('非数字与非法值回落到默认值', () {
      GStorage.setting.put('player_seek_step', 'abc');
      expect(Pref.playerSeekStep, Pref.playerSeekStepDefault);
      expect(Pref.normalizeSeekStep(double.nan), Pref.playerSeekStepDefault);
    });

    test('写入时按 0.1 秒取整', () {
      Pref.playerSeekStep = 92.34;
      expect(Pref.playerSeekStep, 92.3);
    });
  });

  group('进度条游标', () {
    /// 游标位置换算成进度条上的比例, 便于断言.
    ///
    /// 游标在可用区间内按比例定位, 两端各留半个游标宽度, 这里去掉这段内缩.
    double thumbRatio(WidgetTester tester) {
      const thumbSize = 11.0;
      final bar = tester.getRect(find.byType(PlayerProgressBar));
      final thumb = tester.getCenter(
        find.byKey(const ValueKey('player-progress-thumb')),
      );
      return (thumb.dx - bar.left - thumbSize / 2) / (bar.width - thumbSize);
    }

    testWidgets('手势拖动过程中游标实时跟随, 松手后停在目标位置', (tester) async {
      final controller = _Controller();
      await _mount(tester, controller);
      // 初始位置 5 分钟 / 总长 20 分钟.
      expect(thumbRatio(tester), closeTo(0.25, 0.001));

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(PlayerGestureDetector)),
      );
      await gesture.moveBy(const Offset(60, 0));
      await tester.pump();
      // 跨度 90 秒: 从 5 分钟右移 60 像素, 播放器宽度 640.
      final moved = thumbRatio(tester);
      expect(moved, closeTo((300 + 90 * 60 / 640) / 1200, 0.001));
      expect(moved, greaterThan(0.25));

      await gesture.moveBy(const Offset(60, 0));
      await tester.pump();
      final further = thumbRatio(tester);
      expect(further, greaterThan(moved));
      expect(controller.player.seeks, isEmpty);

      await gesture.up();
      await tester.pump();
      // 松手提交跳转, 播放器还没上报新位置时游标仍停在目标处.
      expect(controller.player.seeks, hasLength(1));
      expect(thumbRatio(tester), closeTo(further, 0.001));

      // 播放器上报新位置后交还真实进度.
      controller.player.currentPosition = controller.player.seeks.last;
      controller.player.notifyListeners();
      await tester.pump();
      expect(thumbRatio(tester), closeTo(further, 0.001));

      controller.player.currentPosition = const Duration(minutes: 10);
      controller.player.notifyListeners();
      await tester.pump();
      expect(thumbRatio(tester), closeTo(0.5, 0.001));

      await tester.pumpWidget(const SizedBox.shrink());
      controller.player.dispose();
      // 双击识别器会留下待定定时器, 等它自然结束.
      await tester.pump(const Duration(milliseconds: 400));
    });

    testWidgets('落在取消区的拖动让游标回到真实进度', (tester) async {
      final controller = _Controller();
      await _mount(tester, controller);
      expect(thumbRatio(tester), closeTo(0.25, 0.001));

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(PlayerGestureDetector)),
      );
      await gesture.moveBy(const Offset(60, 0));
      await tester.pump();
      expect(thumbRatio(tester), greaterThan(0.25));

      // 移到左上角取消区, 松手后既没有跳转, 游标也回到原处.
      await gesture.moveTo(tester.getTopLeft(find.byType(PlayerGestureDetector)));
      await tester.pump();
      await gesture.up();
      await tester.pump();
      expect(controller.player.seeks, isEmpty);
      expect(thumbRatio(tester), closeTo(0.25, 0.001));

      await tester.pumpWidget(const SizedBox.shrink());
      controller.player.dispose();
      await tester.pump(const Duration(milliseconds: 400));
    });

    testWidgets('全屏拖动时控制条与游标一起出现', (tester) async {
      final controller = _Controller();
      await _mount(tester, controller, fullscreen: true);
      // 全屏静置后控制条自动隐藏.
      await tester.pump(const Duration(seconds: 5));
      expect(find.byType(PlayerProgressBar), findsNothing);

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(PlayerGestureDetector)),
      );
      await gesture.moveBy(const Offset(60, 0));
      await tester.pump();
      expect(find.byType(PlayerProgressBar), findsOneWidget);
      expect(thumbRatio(tester), greaterThan(0.25));

      await gesture.up();
      await tester.pump();
      // 松手后重新开始计时隐藏.
      await tester.pump(const Duration(seconds: 5));
      expect(find.byType(PlayerProgressBar), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      controller.player.dispose();
    });
  });
}
