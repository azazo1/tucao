import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:tucao/common/widgets/cc/cc_peek_thanks.dart';
import 'package:tucao/common/widgets/cc/comic_speech_bubble.dart';
import 'package:tucao/common/widgets/loading_widget.dart';
import 'package:tucao/http/ad_http.dart';
import 'package:tucao/models/user.dart';
import 'package:tucao/pages/ad/widgets/ad_feed.dart';
import 'package:tucao/pages/ad/widgets/ad_finished_panel.dart';
import 'package:tucao/services/account_service.dart';

class _Account extends AccountService {
  @override
  // 测试只使用注入的账号状态, 不初始化缓存或网络.
  // ignore: must_call_super
  void onInit() {}
}

class _Routes extends NavigatorObserver {
  TransitionRoute<dynamic>? lastPopped;

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    if (route is TransitionRoute<dynamic>) lastPopped = route;
  }
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
  late _Routes routes;

  setUp(() {
    Get.testMode = true;
    account = _Account()..user.value = _user;
    Get.put<AccountService>(account);
    navigator = GlobalKey<NavigatorState>();
    routes = _Routes();
  });

  tearDown(() => Get.reset());

  Future<void> showFeed(
    WidgetTester tester,
    AdReporter reporter, {
    List<AdItem> ads = const [_ad],
    bool accessible = false,
    double textScale = 1,
    AdLoader? loadAds,
  }) async {
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigator,
      navigatorObservers: [routes],
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
          loadAds: loadAds ?? (({CancelToken? cancelToken}) async => ads),
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

  Future<void> finishPop(WidgetTester tester) async {
    final route = routes.lastPopped!;
    final duration = route.reverseTransitionDuration;
    var completed = false;
    unawaited(route.completed.then((_) { completed = true; }));
    await tester.pump();
    await tester.pump(duration);
    // 等退出 Overlay 的帧结束, 不用 pumpAndSettle 把感谢动画一起播完.
    for (var frame = 0; frame < 10 && !completed; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(completed, isTrue);
    await tester.pump();
  }

  Future<void> returnFromAd(WidgetTester tester) async {
    navigator.currentState!.pop();
    await finishPop(tester);
  }

  /// 等待依赖异步资源或下一帧才更新的状态, 不依赖固定的 pump 次数.
  Future<void> pumpUntil(
    WidgetTester tester,
    Finder finder, {
    required bool present,
    int maxFrames = 400,
  }) async {
    for (var frame = 0; frame < maxFrames; frame++) {
      if (finder.evaluate().isNotEmpty == present) return;
      await tester.pump(const Duration(milliseconds: 16));
    }
    fail('等待 ${finder.description} ${present ? '出现' : '消失'} 超时');
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
    await finishPop(tester);
    await pumpUntil(tester, find.byType(CcPeekThanks), present: true);
    final peekBubble = find.descendant(
      of: find.byType(CcPeekThanks),
      matching: find.byType(ComicSpeechBubble),
    );
    expect(
      tester.widget<ComicSpeechBubble>(peekBubble).tail,
      ComicBubbleTail.right,
    );
    expect(find.byType(AdFinishedPanel), findsNothing);
    expect(find.byKey(const ValueKey('ad-t1')), findsNothing);
    expect(reports, 1);
    // 感谢动画要等图集加载后才开始, 按实际消失时机等待.
    await pumpUntil(tester, find.byType(CcPeekThanks), present: false);
    await tester.pump();
    final finished = find.byType(AdFinishedPanel);
    expect(finished, findsOneWidget);
    expect(tester.widget<AdFinishedPanel>(finished).completedHere, isTrue);
    final still = find.descendant(of: finished, matching: find.byType(Image));
    expect(tester.widget<Image>(still).image, const AssetImage(CcPeekThanks.stillAsset));
    await tester.pump(const Duration(seconds: 8));
    expect(finished, findsOneWidget);
    expect(find.byType(CcPeekThanks), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('初次空列表也显示静态感谢, 不推断今日是否看完', (tester) async {
    var reports = 0;
    await showFeed(tester, (_) async { reports++; return true; }, ads: const []);
    final finished = find.byType(AdFinishedPanel);
    expect(finished, findsOneWidget);
    expect(tester.widget<AdFinishedPanel>(finished).completedHere, isFalse);
    expect(find.byType(CcPeekThanks), findsNothing);
    expect(reports, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('加载失败显示重试而不是空列表感谢', (tester) async {
    await showFeed(tester, (_) async => true,
        loadAds: ({CancelToken? cancelToken}) async => throw StateError('load failed'));
    expect(find.byType(ErrorWidgetView), findsOneWidget);
    expect(find.byType(AdFinishedPanel), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('还有未看或未成功上报的广告时不显示收尾页', (tester) async {
    await showFeed(tester, (id) async => id == 't1', ads: const [_ad, _otherAd]);
    await openAd(tester);
    await returnFromAd(tester);
    await tester.pump(CcPeekThanks.duration);
    await tester.pump();
    expect(find.byKey(const ValueKey('ad-t2')), findsOneWidget);
    expect(find.byType(AdFinishedPanel), findsNothing);
    await openAd(tester, 't2');
    await returnFromAd(tester);
    expect(find.byKey(const ValueKey('ad-t2')), findsOneWidget);
    expect(find.byType(AdFinishedPanel), findsNothing);
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
    await pumpUntil(tester, find.byType(CcPeekThanks), present: true);
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
    await pumpUntil(tester, find.byType(CcPeekThanks), present: true);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await pumpUntil(tester, find.byType(CcPeekThanks), present: false);
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
    expect(find.byType(AdFinishedPanel), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('矮屏收尾页按可用高度缩小人物并贴底', (tester) async {
    tester.view.physicalSize = const Size(800, 300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: AdFinishedPanel(completedHere: true)),
    ));
    await tester.pump();
    expect(tester.takeException(), isNull);
    final panel = find.byType(AdFinishedPanel);
    final image = find.descendant(of: panel, matching: find.byType(Image));
    expect(image, findsOneWidget);
    expect(tester.getSize(image).height, lessThan(232));
    expect(
      tester.getBottomLeft(image).dy,
      moreOrLessEquals(tester.getBottomLeft(panel).dy),
    );
    expect(
      find.descendant(of: panel, matching: find.byType(ShaderMask)),
      findsOneWidget,
    );
    final bubble = find.descendant(
      of: panel,
      matching: find.byType(ComicSpeechBubble),
    );
    expect(
      tester.widget<ComicSpeechBubble>(bubble).tail,
      ComicBubbleTail.right,
    );
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
