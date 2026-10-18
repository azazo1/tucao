import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tucao/common/vip.dart';
import 'package:tucao/common/widgets/vip_gold.dart';
import 'package:tucao/http/space_http.dart';
import 'package:tucao/http/vip_http.dart';
import 'package:tucao/models/reply.dart';
import 'package:tucao/models/user.dart';
import 'package:tucao/pages/reply/widgets/comment_tile.dart';

/// 破会员标记的判定, 解析与呈现测试.
///
/// 站点的会员信息分两处: 登录接口的 vip 字段, 以及网页端给破会员昵称加的
/// 颜色, 样本都按真实响应裁剪而来.
void main() {
  group('破会员判定', () {
    test('接口的 vip 取值兼容字符串与布尔', () {
      expect(Vip.fromApiValue('1'), isTrue);
      expect(Vip.fromApiValue(1), isTrue);
      expect(Vip.fromApiValue(true), isTrue);
      expect(Vip.fromApiValue('0'), isFalse);
      expect(Vip.fromApiValue(false), isFalse);
      expect(Vip.fromApiValue(null), isFalse);
    });

    test('只有站点的会员金色算会员, 其它颜色不算', () {
      expect(Vip.hasNicknameColor('color:#c07c32;'), isTrue);
      expect(Vip.hasNicknameColor('COLOR: #C07C32'), isTrue);
      expect(Vip.hasNicknameColor('color:rgb(192, 124, 50);'), isTrue);
      // 站内推广用的是灰色, 不能当会员.
      expect(Vip.hasNicknameColor('color:#666;'), isFalse);
      expect(Vip.hasNicknameColor(''), isFalse);
      expect(Vip.hasNicknameColor(null), isFalse);
    });

    test('登录用户按 vip 字段标记会员', () {
      final vip = UserModel.fromJson({
        'userid': '453817',
        'username': 'azo1',
        'vip': '1',
      });
      expect(vip.isVip, isTrue);
      // 本地缓存回写后重新解析结果不变.
      expect(UserModel.fromJson(vip.toJson()).isVip, isTrue);
      expect(
        UserModel.fromJson({'userid': '1', 'username': 'someone'}).isVip,
        isFalse,
      );
    });
  });

  group('评论页会员解析', () {
    late List<int> uids;

    setUpAll(() {
      final raw = File('test/fixtures/comment_vip.html').readAsStringSync();
      uids = VipHttp.parseCommentVipUids(raw);
    });

    test('取到昵称带金色的会员 uid', () {
      expect(uids, contains(453082));
    });

    test('普通用户与站内推广不算会员', () {
      expect(uids, isNot(contains(453580)));
      // 推广那条没有 uid 链接, 解析时直接跳过.
      expect(uids, hasLength(1));
    });

    test('空响应不报错', () {
      expect(VipHttp.parseCommentVipUids(''), isEmpty);
      expect(VipHttp.parseCommentVipUids('0'), isEmpty);
    });
  });

  group('评论用户记录解析', () {
    late ReplyPage page;

    setUpAll(() {
      final raw = File(
        'test/fixtures/reply_nested_nickname.json',
      ).readAsStringSync();
      page = ReplyPage.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    });

    test('nickname 是用户对象时取昵称而不是 map 文本', () {
      expect(page.list, hasLength(2));
      // 第一条没设昵称, 退回用户名; 第二条取到昵称.
      expect(page.list[0].userName, 'zzx715450884');
      expect(page.list[1].userName, '雨歌丸');
    });

    test('从用户记录里读出会员标记', () {
      expect(page.list[0].isVip, isTrue);
      expect(page.list[1].isVip, isFalse);
    });
  });

  group('用户空间会员标记', () {
    test('昵称带会员颜色时判定为破会员', () {
      const raw =
          '<div class="sheader"><img class="avatar" src="/avatar.jpg" />'
          '<h1 style="color:#c07c32;">azo1</h1><p>正义, 1元1次</p></div>';
      final page = SpaceHttp.parseSpaceHtml(raw, 453817, 1);
      expect(page.info.userName, 'azo1');
      expect(page.info.isVip, isTrue);
    });

    test('普通用户的空间页没有会员颜色', () {
      final raw = File('test/fixtures/space.html').readAsStringSync();
      expect(SpaceHttp.parseSpaceHtml(raw, 9599, 1).info.isVip, isFalse);
    });
  });

  group('评论昵称呈现', () {
    ReplyModel comment() => const ReplyModel(
      id: '1',
      commentId: 'content_11-1-1',
      userId: 35929,
      userName: '测试用户',
      content: '沙发',
    );

    Future<Text> pumpName(WidgetTester tester, {required bool isVip}) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CommentTile(
              comment: comment(),
              isVip: isVip,
              supportCount: 0,
              supported: false,
              onSupport: () {},
              onReply: () {},
            ),
          ),
        ),
      );
      return tester.widget<Text>(find.text('测试用户'));
    }

    testWidgets('破会员昵称用站点金色', (tester) async {
      final name = await pumpName(tester, isVip: true);
      expect(name.style?.color, Vip.nicknameColor);
    });

    testWidgets('普通用户昵称不用金色', (tester) async {
      final name = await pumpName(tester, isVip: false);
      expect(name.style?.color, isNot(Vip.nicknameColor));
    });
  });

  group('破会员金色呈现', () {
    test('金色只是客户端的展示色, 站点的判定色不受影响', () {
      expect(Vip.hasNicknameColor('color:#c07c32;'), isTrue);
      expect(Vip.gold, isNot(Vip.nicknameColor));
      expect(Vip.goldDeep, isNot(Vip.nicknameColor));
    });

    testWidgets('流光在减弱动画时静止, 卸载后不留 ticker', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: const Scaffold(
                body: Center(child: VipGold(child: Text('破会员'))),
              ),
            ),
          ),
        ),
      );
      expect(find.byType(VipGold), findsOneWidget);
      // 减弱动画时不跑流光, 但仍要确认卸载后控制器不留下还在跑的 ticker.
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('流光开着动画时也能正常卸载', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Center(child: VipGold(child: Text('破会员')))),
        ),
      );
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byType(VipGold), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}
