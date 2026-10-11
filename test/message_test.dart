import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tucao/http/message_http.dart';

void main() {
  group('私信收件箱解析', () {
    late List<dynamic> list;

    setUpAll(() {
      final raw = File('test/fixtures/message_inbox.html').readAsStringSync();
      list = MessageHttp.parseInboxHtml(raw);
    });

    test('解析出消息条目', () {
      expect(list, hasLength(2));
      expect(list[0].id, '1001');
      expect(list[0].username, '张三');
      expect(list[0].message, '你好, 这是第一条私信');
      expect(list[0].time, '2026-10-01 10:00');
      expect(list[0].avatar, '/avatar/1.jpg');
    });

    test('按 messageid 去重', () {
      // 第三条与第二条的 messageid 相同, 只保留一条.
      expect(list.map((e) => e.id).toList(), ['1001', '1002']);
    });

    test('链接里没有 messageid 的条目被忽略', () {
      expect(list.any((e) => e.username == '王五'), isFalse);
    });

    test('空页面返回空列表而不是抛异常', () {
      expect(MessageHttp.parseInboxHtml('<html></html>'), isEmpty);
    });
  });

  group('私信详情解析', () {
    late List<dynamic> list;

    setUpAll(() {
      final raw = File('test/fixtures/message_detail.html').readAsStringSync();
      // uid 为 200 的是自己, 由头像链接判断归属.
      list = MessageHttp.parseDetailHtml(raw, '200');
    });

    test('解析出会话消息', () {
      expect(list, hasLength(3));
      expect(list[0].content, '对方发来的消息');
      expect(list[0].time, '2026-10-01 10:00');
    });

    test('按 uid 判断消息归属', () {
      expect(list[0].isMine, isFalse);
      expect(list[1].isMine, isTrue);
      expect(list[2].isMine, isFalse);
    });

    test('保留发送者 uid 供回复使用', () {
      expect(list[0].userId, '100');
      expect(list[1].userId, '200');
    });

    test('未登录时所有消息都不算自己的', () {
      final raw = File('test/fixtures/message_detail.html').readAsStringSync();
      final result = MessageHttp.parseDetailHtml(raw, '');
      expect(result.every((e) => !e.isMine), isTrue);
    });
  });
}
