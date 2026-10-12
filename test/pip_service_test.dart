import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tucao/services/pip_service.dart';

/// 画中画通道, 字段名与 PipController.kt 中的取值保持一致.
const _channel = MethodChannel('com.azazo1.tucao/pip');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(_channel, null));

  test('没有平台实现时按不支持处理, 不抛异常', () async {
    expect(await PipService.instance.isSupported(), isFalse);
    expect(await PipService.instance.enter(), isFalse);
  });

  test('进入小窗时把画面尺寸与动画起点交给平台', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(_channel, (call) async {
      calls.add(call);
      return true;
    });

    final entered = await PipService.instance.enter(
      width: 1920,
      height: 1080,
      // 用 LTRB 构造, 与下面断言的四个边界一一对应.
      sourceRect: const Rect.fromLTRB(10, 20, 110, 80),
    );

    expect(entered, isTrue);
    expect(calls.single.method, 'enter');
    expect(calls.single.arguments, {
      'width': 1920,
      'height': 1080,
      'left': 10,
      'top': 20,
      'right': 110,
      'bottom': 80,
    });
  });

  test('画面尺寸缺失或非法时不传给平台', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(_channel, (call) async {
      calls.add(call);
      return true;
    });

    await PipService.instance.enter();
    expect(calls.last.arguments, isEmpty);

    await PipService.instance.setAutoEnter(enabled: false, width: 0, height: -1);
    expect(calls.last.arguments, {'enabled': false});
  });

  test('平台上报的小窗状态通知到界面', () async {
    final states = <bool>[];
    void listener() => states.add(PipService.instance.inPipMode.value);
    PipService.instance.inPipMode.addListener(listener);
    addTearDown(() => PipService.instance.inPipMode.removeListener(listener));

    Future<void> notify(bool inPip) async {
      await messenger.handlePlatformMessage(
        _channel.name,
        const StandardMethodCodec().encodeMethodCall(
          MethodCall('pipModeChanged', inPip),
        ),
        (_) {},
      );
    }

    await notify(true);
    await notify(false);

    expect(states, [true, false]);
  });
}
