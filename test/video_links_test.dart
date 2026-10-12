import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tucao/common/constants.dart';
import 'package:tucao/pages/video/widgets/video_link_menu.dart';
import 'package:tucao/utils/site_links.dart';

void main() {
  test('视频链接只包含站内编号和从 1 开始的分P锚点', () {
    final first = SiteLinks.video('4107869');
    final second = SiteLinks.video('4107869', part: 1);
    expect(first?.scheme, 'https');
    expect(first?.host, Constants.host);
    expect(first?.path, '/play/h4107869/');
    expect(first?.fragment, '1');
    expect(second?.fragment, '2');
    expect(second?.query, isEmpty);
    expect(second?.userInfo, isEmpty);
  });

  test('空编号和路径注入不能生成外部打开链接', () {
    for (final hid in [
      '',
      '0',
      '000',
      'h123',
      '../123',
      '12#3',
      'https://example.com',
      '12/3',
    ]) {
      expect(SiteLinks.video(hid), isNull);
    }
    expect(SiteLinks.video('123', part: -1), isNull);
  });

  testWidgets('复制当前分P链接, 不触发浏览器操作', (tester) async {
    String? copied;
    var opens = 0;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(
            actions: [
              VideoLinkMenu(
                hid: '4107869',
                part: 1,
                onOpenWebsite: () => opens++,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.tap(
      find.byWidgetPredicate((widget) => widget is PopupMenuButton),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.link));
    await tester.pumpAndSettle();
    expect(copied, SiteLinks.video('4107869', part: 1).toString());
    expect(opens, 0);
    expect(find.byType(SnackBar), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('浏览器菜单触发页面统一处理, 不复制视频直链', (tester) async {
    var opens = 0;
    var copies = 0;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copies++;
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(
            actions: [
              VideoLinkMenu(
                hid: '4107869',
                part: 0,
                onOpenWebsite: () => opens++,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.tap(
      find.byWidgetPredicate((widget) => widget is PopupMenuButton),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.open_in_browser));
    await tester.pumpAndSettle();
    expect(opens, 1);
    expect(copies, 0);
  });

  testWidgets('无效视频编号禁用菜单', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(
            actions: [
              VideoLinkMenu(
                hid: '',
                part: 0,
                onOpenWebsite: () => fail('不应打开浏览器'),
              ),
            ],
          ),
        ),
      ),
    );
    final menu = tester.widget<PopupMenuButton>(
      find.byWidgetPredicate((widget) => widget is PopupMenuButton),
    );
    expect(menu.enabled, isFalse);
    await tester.tap(
      find.byWidgetPredicate((widget) => widget is PopupMenuButton),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.open_in_browser), findsNothing);
  });
}
