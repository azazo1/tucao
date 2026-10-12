import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tucao/pages/video/widgets/player_gesture.dart';
import 'package:tucao/plugin/player/player_controller.dart';
import 'package:tucao/plugin/player/tucao_player.dart';

class _Player implements TucaoPlayer {
  @override
  Duration get position => const Duration(seconds: 30);

  @override
  Duration get duration => const Duration(seconds: 120);

  @override
  double get volume => 50;

  @override
  double get speed => 1;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Controller implements PlayerPageController {
  @override
  final player = _Player();
  final seeks = <Duration>[];
  final volumes = <double>[];
  final speeds = <double>[];
  int toggles = 0;

  @override
  Future<void> seek(Duration position) async => seeks.add(position);

  @override
  Future<void> setVolume(double volume) async => volumes.add(volume);

  @override
  Future<void> setSpeed(double speed) async => speeds.add(speed);

  @override
  Future<void> togglePlay() async => toggles++;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<Offset> _mount(
  WidgetTester tester,
  _Controller controller, {
  VoidCallback? onToggleControls,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Stack(
          children: [
            Positioned(
              left: 200,
              top: 120,
              width: 400,
              height: 240,
              child: PlayerGestureDetector(
                controller: controller,
                onToggleControls: onToggleControls ?? () {},
              ),
            ),
          ],
        ),
      ),
    ),
  );
  return tester.getTopLeft(find.byType(PlayerGestureDetector));
}

void main() {
  const cancelled = ValueKey('seek-cancel-indicator');

  for (final corner in [const Offset(20, 20), const Offset(380, 20)]) {
    testWidgets('横向 seek 后移入 $corner 显示取消, 松手不 seek', (tester) async {
      final controller = _Controller();
      final origin = await _mount(tester, controller);
      final gesture = await tester.startGesture(
        origin + const Offset(200, 130),
      );
      await gesture.moveBy(const Offset(40, 0));
      await tester.pump();
      expect(find.byKey(cancelled), findsNothing);
      await gesture.moveTo(origin + corner);
      await tester.pump();
      expect(find.byKey(cancelled), findsOneWidget);
      await gesture.up();
      await tester.pump();
      expect(controller.seeks, isEmpty);
      expect(find.byKey(cancelled), findsNothing);
      await tester.dragFrom(
        origin + const Offset(180, 130),
        const Offset(80, 0),
      );
      await tester.pump();
      expect(controller.seeks, hasLength(1));
      await tester.pump(const Duration(milliseconds: 400));
    });
  }

  testWidgets('取消区移回正常区域恢复 seek, pointer cancel 清理下一次拖动', (tester) async {
    final controller = _Controller();
    final origin = await _mount(tester, controller);
    final gesture = await tester.startGesture(origin + const Offset(200, 130));
    await gesture.moveBy(const Offset(40, 0));
    await gesture.moveTo(origin + const Offset(380, 20));
    await tester.pump();
    expect(find.byKey(cancelled), findsOneWidget);
    await gesture.moveTo(origin + const Offset(300, 130));
    await tester.pump();
    expect(find.byKey(cancelled), findsNothing);
    await gesture.up();
    await tester.pump();
    expect(controller.seeks, [const Duration(seconds: 55)]);

    final abandoned = await tester.startGesture(
      origin + const Offset(200, 130),
    );
    await abandoned.moveBy(const Offset(40, 0));
    await abandoned.moveTo(origin + const Offset(20, 20));
    await tester.pump();
    expect(find.byKey(cancelled), findsOneWidget);
    await abandoned.cancel();
    await tester.pump();
    expect(find.byKey(cancelled), findsNothing);
    expect(controller.seeks, hasLength(1));
    await tester.dragFrom(origin + const Offset(180, 130), const Offset(80, 0));
    await tester.pump();
    expect(controller.seeks, hasLength(2));
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('角落起点可拖出并 seek, 真正按下点参与进度计算', (tester) async {
    final controller = _Controller();
    final origin = await _mount(tester, controller);
    final gesture = await tester.startGesture(origin + const Offset(20, 20));
    await gesture.moveBy(const Offset(150, 0));
    await tester.pump();
    expect(find.byKey(cancelled), findsNothing);
    await gesture.up();
    await tester.pump();
    expect(controller.seeks, [const Duration(milliseconds: 67500)]);
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('角落点击和阈值内移动不取消, 纵向双击和长按保持原行为', (tester) async {
    final controller = _Controller();
    var controls = 0;
    final origin = await _mount(
      tester,
      controller,
      onToggleControls: () => controls++,
    );
    final tap = await tester.startGesture(origin + const Offset(20, 20));
    await tap.moveBy(const Offset(6, 0));
    await tester.pump();
    expect(find.byKey(cancelled), findsNothing);
    await tap.up();
    await tester.pump(const Duration(milliseconds: 350));
    expect(controls, 1);
    expect(controller.seeks, isEmpty);

    await tester.dragFrom(origin + const Offset(20, 20), const Offset(0, 80));
    await tester.pump();
    expect(controller.volumes, hasLength(1));
    expect(controller.volumes.single, closeTo(50 - 80 / 240 * 100, 0.01));
    await tester.dragFrom(
      origin + const Offset(300, 130),
      const Offset(0, -80),
    );
    await tester.pump();
    expect(controller.volumes, hasLength(1));
    expect(controller.seeks, isEmpty);

    await tester.tapAt(origin + const Offset(380, 20));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(origin + const Offset(380, 20));
    await tester.pump(const Duration(milliseconds: 350));
    expect(controller.toggles, 1);
    final hold = await tester.startGesture(origin + const Offset(20, 20));
    await tester.pump(const Duration(milliseconds: 600));
    expect(controller.speeds, [3]);
    await hold.up();
    await tester.pump();
    expect(controller.speeds, [3, 1]);
    await tester.pump(const Duration(milliseconds: 400));
  });
}
