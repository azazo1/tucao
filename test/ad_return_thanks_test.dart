import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:tucao/common/widgets/cc/cc_peek_thanks.dart';
import 'package:tucao/http/ad_http.dart';
import 'package:tucao/models/user.dart';
import 'package:tucao/pages/ad/widgets/ad_feed.dart';
import 'package:tucao/services/account_service.dart';

class _Account extends AccountService {
  @override
  // 测试只使用注入的账号状态, 不初始化缓存或网络.
  // ignore: must_call_super
  void onInit() {}
}

const _user = UserModel(userId: 1, userName: 'viewer');
const _ad = AdItem(
  adId: 't1', loggedIn: true,
  imageUrl: 'https://example.invalid/banner.png',
  linkUrl: 'https://example.invalid/ad',
);
const _otherAd = AdItem(
  adId: 't2', loggedIn: true,
  imageUrl: 'https://example.invalid/other.png',
  linkUrl: 'https://example.invalid/other',
);

void main() {
  late _Account account;
  late GlobalKey<NavigatorState> navigator;

  setUp(() {
    Get.testMode = true;
    account = _Account()..user.value = _user;
    Get.put<AccountService>(account);
    navigator = GlobalKey<NavigatorState>();
  });

  tearDown(() => Get.reset());

  Future<void> showFeed(
    WidgetTester tester,
    AdReporter reporter, {
    List<AdItem> ads = const [_ad],
    bool accessible = false,
    double textScale = 1,
  }) async {
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigator,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          disableAnimations: true,
          accessibleNavigation: accessible,
          textScaler: TextScaler.linear(textScale),
        ),
        child: child!,
      ),
      home: Scaffold(
        body: AdFeed(
          loadAds: ({CancelToken? cancelToken}) async => ads,
          reportClick: reporter,
          buildAdPage: (_) => const Scaffold(key: ValueKey('ad-detail')),
        ),
      ),
    ));
    await tester.pump();
  }

  Future<void> openAd(WidgetTester tester, [String id = 't1']) async {
    await tester.tap(find.byKey(ValueKey('ad-$id')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('ad-detail')), findsOneWidget);
  }

  Future<void> returnFromAd(WidgetTester tester) async {
    navigator.currentState!.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
  }

  testWidgets('成功上报与恢复前台都不在广告页弹出, 完整退出后才感谢', (tester) async {
    var reports = 0;
    final result = Completer<bool>();
    await showFeed(tester, (_) { reports++; return result.future; });
    await openAd(tester);
    result.complete(true);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.byType(CcPeekThanks, skipOffstage: false), findsNothing);
    navigator.currentState!.pop();
    // 仅发出 pop 还没有完成退出转场.
    expect(find.byType(CcPeekThanks, skipOffstage: false), findsNothing);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(find.byType(CcPeekThanks), findsOneWidget);
    expect(find.byKey(const ValueKey('ad-t1')), findsNothing);
    expect(reports, 1);
    await tester.pump(CcPeekThanks.duration);
    await tester.pump();
    expect(find.byType(CcPeekThanks), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('先返回则等待上报, 失败不弹且允许重新尝试', (tester) async {
    var reports = 0;
    final result = Completer<bool>();
    await showFeed(tester, (_) { reports++; return result.future; });
    await openAd(tester);
    await returnFromAd(tester);
    expect(find.byType(CcPeekThanks), findsNothing);
    result.complete(false);
    await tester.pump();
    expect(find.byType(CcPeekThanks), findsNothing);
    expect(find.byKey(const ValueKey('ad-t1')), findsOneWidget);
    await openAd(tester);
    expect(reports, 2);
    await returnFromAd(tester);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('旧上报晚到不打断下一次看广告, 新点击返回后可感谢', (tester) async {
    final first = Completer<bool>();
    final second = Completer<bool>();
    await showFeed(tester, (id) => id == 't1' ? first.future : second.future,
        ads: const [_ad, _otherAd]);
    await openAd(tester);
    await returnFromAd(tester);
    await openAd(tester, 't2');
    first.complete(true);
    await tester.pump();
    expect(find.byType(CcPeekThanks, skipOffstage: false), findsNothing);
    await returnFromAd(tester);
    second.complete(true);
    await tester.pump();
    expect(find.byType(CcPeekThanks), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('等待上报期间离开列表, 旧结果不能在再次返回时补弹', (tester) async {
    final result = Completer<bool>();
    await showFeed(tester, (_) => result.future);
    await openAd(tester);
    await returnFromAd(tester);
    unawaited(navigator.currentState!.push<void>(MaterialPageRoute<void>(
      builder: (_) => const Scaffold(),
    )));
    await tester.pumpAndSettle();
    result.complete(true);
    await tester.pump();
    await returnFromAd(tester);
    expect(find.byType(CcPeekThanks), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('感谢遇到后台立即撤下, 恢复前台不重播', (tester) async {
    await showFeed(tester, (_) async => true);
    await openAd(tester);
    await returnFromAd(tester);
    expect(find.byType(CcPeekThanks), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.byType(CcPeekThanks), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('返回后账号变化或组件卸载会丢弃在途结果', (tester) async {
    final result = Completer<bool>();
    await showFeed(tester, (_) => result.future);
    await openAd(tester);
    await returnFromAd(tester);
    account.user.value = const UserModel(userId: 2, userName: 'other');
    result.complete(true);
    await tester.pump();
    expect(find.byType(CcPeekThanks), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    final disposedResult = Completer<bool>();
    await showFeed(tester, (_) => disposedResult.future);
    await openAd(tester);
    await returnFromAd(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    disposedResult.complete(true);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('未登录广告不发送上报也不展示成功感谢', (tester) async {
    var reports = 0;
    await showFeed(tester, (_) async { reports++; return true; }, ads: const [
      AdItem(adId: 't1', loggedIn: false,
          imageUrl: 'https://example.invalid/guest.png',
          linkUrl: 'https://example.invalid/guest'),
    ]);
    await openAd(tester);
    await returnFromAd(tester);
    expect(reports, 0);
    expect(find.byType(CcPeekThanks), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('窄屏大字与读屏保留静态感谢, 点击可收起', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await showFeed(tester, (_) async => true, accessible: true, textScale: 2);
    await openAd(tester);
    await returnFromAd(tester);
    await tester.pump(const Duration(seconds: 8));
    final thanks = find.byType(CcPeekThanks);
    expect(thanks, findsOneWidget);
    final image = find.descendant(of: thanks, matching: find.byType(Image));
    expect(tester.widget<Image>(image).image, const AssetImage(CcPeekThanks.stillAsset));
    await tester.tap(image);
    await tester.pump();
    expect(thanks, findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('九帧从扶边探头到收手, 分镜边界不越界', () {
    var elapsed = 0;
    for (var frame = 0; frame < CcPeekThanks.frameDurations.length; frame++) {
      expect(CcPeekThanks.frameAt(Duration(milliseconds: elapsed)), frame);
      elapsed += CcPeekThanks.frameDurations[frame];
      expect(CcPeekThanks.frameAt(Duration(milliseconds: elapsed - 1)), frame);
    }
    expect(elapsed, CcPeekThanks.duration.inMilliseconds);
    expect(CcPeekThanks.frameAt(const Duration(days: 1)), 8);
  });
}
