import 'package:canvas_danmaku/canvas_danmaku.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:tucao/models/danmaku.dart';
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
  @override
  String get hid => '1';
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

Future<void> _mount(WidgetTester tester, _Controller controller) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 640,
          height: 360,
          child: VideoPlayerView(
            controller: controller,
            fullscreen: false,
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

  testWidgets('左下角按钮按设置秒数前进, 越过片尾时停在片尾', (tester) async {
    final controller = _Controller();
    await _mount(tester, controller);
    expect(find.text('1:30'), findsOneWidget);

    await tester.tap(find.text('1:30'));
    await tester.pump();
    expect(controller.player.seeks, [const Duration(seconds: 390)]);

    // 时长未知时不显示按钮, 避免无意义的跳转.
    controller.player.currentDuration = Duration.zero;
    controller.player.notifyListeners();
    await tester.pump();
    expect(find.text('1:30'), findsNothing);

    controller.player.currentDuration = const Duration(minutes: 20);
    controller.player.currentPosition = const Duration(
      minutes: 19,
      seconds: 30,
    );
    controller.player.notifyListeners();
    await tester.pump();
    await tester.tap(find.text('1:30'));
    await tester.pump();
    expect(controller.player.seeks.last, const Duration(minutes: 20));

    await tester.pumpWidget(const SizedBox.shrink());
    controller.player.dispose();
  });

  testWidgets('调整设置后按钮文字与跳转距离同步变化', (tester) async {
    Pref.playerSeekStep = 85.5;
    final controller = _Controller();
    await _mount(tester, controller);
    expect(find.text('1:25.5'), findsOneWidget);
    await tester.tap(find.text('1:25.5'));
    await tester.pump();
    expect(controller.player.seeks, [
      const Duration(minutes: 5, seconds: 85, milliseconds: 500),
    ]);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.player.dispose();
  });
}
