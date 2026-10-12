import 'dart:async';

import 'package:canvas_danmaku/canvas_danmaku.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:tucao/models/danmaku.dart';
import 'package:tucao/models/danmaku_preferences.dart';
import 'package:tucao/pages/video/widgets/danmaku_settings_sheet.dart';
import 'package:tucao/pages/video/widgets/player_gesture.dart';
import 'package:tucao/pages/video/widgets/player_view.dart';
import 'package:tucao/plugin/player/player_controller.dart';
import 'package:tucao/plugin/player/tucao_player.dart';

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
  String get hid => '1';
  @override
  DanmakuOption get danmakuOption => const DanmakuOption();
  @override
  void attachDanmaku(DanmakuController<DanmakuModel> controller) {}
  @override
  Future<void> togglePlay() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('320宽大字面板滑动预览, 松手保存失败恢复原设置', (tester) async {
    tester.view.physicalSize = const Size(320, 560);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final previews = <DanmakuPreferences>[];
    final saving = Completer<void>();
    var saves = 0;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.8)),
          child: child!,
        ),
        home: Scaffold(
          body: DanmakuSettingsPanel(
            initial: const DanmakuPreferences(opacity: 0.8),
            onChanged: previews.add,
            save: (_) {
              saves++;
              return saving.future;
            },
          ),
        ),
      ),
    );
    final slider = find.byType(Slider).first;
    await tester.ensureVisible(slider);
    await tester.pump();
    final before = tester.widget<Slider>(slider).value;
    final start = tester.getCenter(slider);
    final gesture = await tester.startGesture(start);
    await gesture.moveBy(const Offset(-40, 0));
    await tester.pump();
    expect(previews, isNotEmpty);
    expect(previews.last.opacity, isNot(before));
    expect(saves, 0);
    await gesture.up();
    await tester.pump();
    expect(saves, 1);
    expect(tester.widget<Slider>(slider).onChanged, isNull);
    saving.completeError(StateError('write failed'));
    await tester.pump();
    expect(tester.widget<Slider>(slider).value, before);
    expect(previews.last.opacity, before);
    expect(tester.takeException(), isNull);
    final scroll = find.byKey(const ValueKey('danmaku-settings-scroll'));
    await tester.drag(scroll, const Offset(0, -2400));
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('路由覆盖后失败不触发迟到预览回滚', (tester) async {
    final previews = <DanmakuPreferences>[];
    final saving = Completer<void>();
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: Scaffold(
          body: DanmakuSettingsPanel(
            initial: DanmakuPreferences.defaults,
            onChanged: previews.add,
            save: (_) => saving.future,
          ),
        ),
      ),
    );
    final switchTile = tester.widget<SwitchListTile>(
      find.byType(SwitchListTile).first,
    );
    switchTile.onChanged!(false);
    await tester.pump();
    expect(previews.single.enabled, isFalse);
    navigator.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => const Scaffold(body: SizedBox())),
    );
    await tester.pump(const Duration(milliseconds: 400));
    saving.completeError(StateError('write failed'));
    await tester.pump();
    expect(previews, hasLength(1));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('全屏返回和控制条共同计时隐藏, 单击恢复, 非全屏不显示', (tester) async {
    final controller = _Controller();
    var exits = 0;
    Widget mount(bool fullscreen) => MaterialApp(
      home: Scaffold(
        body: VideoPlayerView(
          controller: controller,
          fullscreen: fullscreen,
          onToggleFullscreen: () => exits++,
          onOpenWebsite: () {},
        ),
      ),
    );
    await tester.pumpWidget(mount(true));
    final back = find.widgetWithIcon(IconButton, Icons.arrow_back);
    expect(back, findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    expect(back, findsNothing);
    expect(find.byType(PlayerProgressBar), findsNothing);
    await tester.tapAt(tester.getCenter(find.byType(PlayerGestureDetector)));
    await tester.pump(const Duration(milliseconds: 350));
    expect(back, findsOneWidget);
    expect(find.byType(PlayerProgressBar), findsOneWidget);
    await tester.tap(back);
    expect(exits, 1);
    await tester.pumpWidget(mount(false));
    expect(back, findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.player.dispose();
    Get.reset();
  });
}
