import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:tucao/common/widgets/cc/cc_thanks_animation.dart';
import 'package:tucao/http/ad_http.dart';
import 'package:tucao/models/user.dart';
import 'package:tucao/pages/ad/ad_list_page.dart';
import 'package:tucao/pages/ad/widgets/ad_feed.dart';
import 'package:tucao/pages/ad/widgets/vip_thanks_panel.dart';
import 'package:tucao/services/account_service.dart';

class _Account extends AccountService {
  @override
  void onInit() {}
}

const _vip = UserModel(userId: 1, userName: 'member', isVip: true);

void main() {
  late _Account account;

  setUp(() {
    Get.testMode = true;
    account = _Account();
    Get.put<AccountService>(account);
  });

  tearDown(() async {
    await Get.reset();
  });

  Future<void> showPage(
    WidgetTester tester,
    AdLoader loadAds, {
    double textScale = 1,
    bool reduceMotion = true,
  }) async {
    await tester.pumpWidget(
      GetMaterialApp(
        theme: ThemeData.dark(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations: reduceMotion,
            textScaler: TextScaler.linear(textScale),
          ),
          child: child!,
        ),
        home: AdListPage(loadAds: loadAds),
      ),
    );
    await tester.pump();
  }

  testWidgets('会员初始进入不请求广告', (tester) async {
    account.user.value = _vip;
    var requests = 0;
    await showPage(tester, ({CancelToken? cancelToken}) async {
      requests++;
      return [];
    });
    expect(requests, 0);
    expect(find.byType(VipThanksPanel), findsOneWidget);
    expect(find.byType(AdFeed), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('会员状态更新移除在途广告, 退出登录后重新加载', (tester) async {
    final pending = Completer<List<AdItem>>();
    CancelToken? firstRequest;
    var requests = 0;
    await showPage(tester, ({CancelToken? cancelToken}) {
      requests++;
      if (requests == 1) firstRequest = cancelToken;
      return requests == 1 ? pending.future : Future.value(<AdItem>[]);
    });
    expect(requests, 1);
    expect(find.byType(AdFeed), findsOneWidget);
    account.user.value = _vip;
    await tester.pump();
    expect(firstRequest?.isCancelled, isTrue);
    pending.complete([]);
    await tester.pump();
    expect(find.byType(AdFeed), findsNothing);
    expect(find.byType(VipThanksPanel), findsOneWidget);
    expect(requests, 1);
    account.user.value = null;
    await tester.pump();
    await tester.pump();
    expect(find.byType(VipThanksPanel), findsNothing);
    expect(find.byType(AdFeed), findsOneWidget);
    expect(requests, 2);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('窄屏大字可滚动, 减弱动画禁用重播并使用静态素材', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    account.user.value = _vip;
    await showPage(tester, ({CancelToken? cancelToken}) async => [], textScale: 2);
    final replay = find.byKey(const ValueKey('cc-thanks-replay'));
    await tester.ensureVisible(replay);
    await tester.pump();
    expect(tester.widget<InkWell>(replay).onTap, isNull);
    final image = tester.widget<Image>(
      find.descendant(of: find.byType(CcThanksAnimation), matching: find.byType(Image)),
    );
    expect(image.image, const AssetImage(CcThanksAnimation.stillAsset));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('点击角色重播感谢动画, 不重新请求广告', (tester) async {
    account.user.value = _vip;
    var requests = 0;
    await showPage(tester, ({CancelToken? cancelToken}) async {
      requests++;
      return [];
    }, reduceMotion: false);
    final replay = find.byKey(const ValueKey('cc-thanks-replay'));
    await tester.ensureVisible(replay);
    expect(tester.widget<CcThanksAnimation>(find.byType(CcThanksAnimation)).replay, 0);
    await tester.tap(replay);
    await tester.pump();
    expect(tester.widget<CcThanksAnimation>(find.byType(CcThanksAnimation)).replay, 1);
    expect(requests, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('分镜时长和边界一致, 收尾不会越过图集', () {
    var elapsed = 0;
    for (var frame = 0; frame < CcThanksAnimation.frameDurations.length; frame++) {
      expect(CcThanksAnimation.frameAt(Duration(milliseconds: elapsed)), frame);
      elapsed += CcThanksAnimation.frameDurations[frame];
      expect(CcThanksAnimation.frameAt(Duration(milliseconds: elapsed - 1)), frame);
    }
    expect(elapsed, CcThanksAnimation.duration.inMilliseconds);
    expect(CcThanksAnimation.frameAt(CcThanksAnimation.duration), 8);
    expect(CcThanksAnimation.frameAt(const Duration(days: 1)), 8);
  });
}
