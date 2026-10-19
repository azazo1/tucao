import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tucao/pages/reply/widgets/reply_input_sheet.dart';

/// 图评入口的行为测试.
///
/// 真实的选图与上传都在平台侧, 这里只验证入口的显示条件与插入结果,
/// 选图通道用 mock 代替.
void main() {
  const channel = MethodChannel('com.azazo1.tucao/image_picker');

  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('没有上传回调时不显示图评入口', (tester) async {
    await tester.pumpWidget(wrap(const ReplyInputSheet(replyToName: '某人')));

    expect(find.byTooltip('图片'), findsNothing);
  });

  testWidgets('非破会员点图片只给提示, 不打开选择器', (tester) async {
    var picked = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          picked = true;
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    await tester.pumpWidget(
      wrap(
        ReplyInputSheet(
          onUploadImage: (bytes, name) async => '[img]x[/img]',
          imageEnabled: false,
        ),
      ),
    );
    await tester.tap(find.byTooltip('图片'));
    await tester.pump();

    expect(find.text('图评是破会员特权, 需要先开通破会员'), findsOneWidget);
    expect(picked, isFalse);

    // 让 snackbar 的计时器走完, 避免测试结束时留下未完成的定时器.
    await tester.pumpAndSettle(const Duration(seconds: 3));
  });

  testWidgets('上传成功后把站点片段插进正文', (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method != 'pickImage') {
            return null;
          }
          return {
            'bytes': Uint8List.fromList([1, 2, 3]),
            'name': 'a.png',
          };
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    await tester.pumpWidget(
      wrap(
        ReplyInputSheet(
          onUploadImage: (bytes, name) async {
            expect(name, 'a.png');
            expect(bytes, hasLength(3));
            return '[img]https://a/b.png[/img]';
          },
        ),
      ),
    );
    await tester.tap(find.byTooltip('图片'));
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller?.text, '[img]https://a/b.png[/img]');
  });
}
