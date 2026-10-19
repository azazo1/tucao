import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tucao/common/constants.dart';
import 'package:tucao/http/message_http.dart';
import 'package:tucao/models/message.dart';

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

  group('系统公告列表解析', () {
    late List<SystemMessage> list;

    setUpAll(() {
      final raw = File(
        'test/fixtures/message_group_list.html',
      ).readAsStringSync();
      list = MessageHttp.parseGroupListHtml(raw);
    });

    test('解析出公告条目', () {
      expect(list, hasLength(2));
      expect(list[0].id, '21');
      expect(list[0].time, '2026-09-17 22:34:37');
    });

    test('标题取摘要第一行, 其余作为摘要', () {
      expect(list[0].title, '做任务, 得破会员');
      expect(
        list[0].summary,
        '破会员有什么主要特权: 1 无广告, 2 亮眼 发布内容都有效',
      );
      expect(list[1].title, '全新 app');
      expect(list[1].summary, isEmpty);
    });

    test('未读标记与头像地址', () {
      expect(list[0].unread, isTrue);
      expect(list[1].unread, isFalse);
      expect(
        list[0].avatar,
        '${Constants.baseUrl}uploadfile/2026/0629/system.png',
      );
      expect(
        list[1].avatar,
        'https://www.tucao.my/uploadfile/2026/0629/system.png',
      );
    });

    test('私信条目与重复的 group_id 都被忽略', () {
      expect(list.map((e) => e.id).toList(), ['21', '19']);
    });

    test('空页面返回空列表而不是抛异常', () {
      expect(MessageHttp.parseGroupListHtml('<html></html>'), isEmpty);
    });
  });

  group('系统公告详情解析', () {
    late SystemMessageDetail detail;

    setUpAll(() {
      final raw = File(
        'test/fixtures/message_group_detail.html',
      ).readAsStringSync();
      detail = MessageHttp.parseGroupDetailHtml(raw);
    });

    test('解析标题与时间', () {
      expect(detail.title, '面板升级公告');
      expect(detail.time, '2026-06-29 14:25:04');
    });

    test('正文按段落与图片分块', () {
      expect(detail.blocks, hasLength(4));
      expect(detail.blocks[0], isA<SystemImage>());
      expect(
        (detail.blocks[0] as SystemImage).url,
        '${Constants.baseUrl}uploadfile/2026/0620/cover.jpg',
      );
      final first = detail.blocks[1] as SystemParagraph;
      expect(first.parts.single.text, '第一段文字');
    });

    test('段落里的链接单独成段并补成绝对地址', () {
      final paragraph = detail.blocks[2] as SystemParagraph;
      expect(
        paragraph.parts.map((e) => e.text).toList(),
        ['带着', '外部链接', '的段落'],
      );
      expect(paragraph.parts[1].url, 'https://store.rg-adguard.net/');
      expect(paragraph.parts[0].url, isNull);
    });

    test('只有空白的段落不产生块', () {
      // 正文里的空行是站点用一行空段落撑出来的, 不该变成空的一段.
      final texts = detail.blocks
          .whereType<SystemParagraph>()
          .expand((block) => block.parts)
          .map((part) => part.text);
      expect(texts.every((text) => text.trim().isNotEmpty), isTrue);
    });

    test('br 换行保留在段落里', () {
      final last = detail.blocks[3] as SystemParagraph;
      expect(last.parts.single.text, '第一行\n第二行');
    });

    test('空页面不抛异常', () {
      final empty = MessageHttp.parseGroupDetailHtml('<html></html>');
      expect(empty.title, isEmpty);
      expect(empty.time, isEmpty);
      expect(empty.blocks, isEmpty);
    });
  });

  group('评论列表解析', () {
    late CommentMessagePage page;

    setUpAll(() {
      final raw = File(
        'test/fixtures/message_comment_list.html',
      ).readAsStringSync();
      page = MessageHttp.parseCommentListHtml(raw);
    });

    test('解析出评论条目', () {
      expect(page.list, hasLength(2));
      expect(page.list[0].title, '感谢@azazo1，写的第三方APP。');
      expect(page.list[0].content, '给力，大佬');
      expect(page.list[0].category, '档案');
      expect(page.list[0].author, '不明');
      expect(page.list[0].time, '2026-10-19');
    });

    test('带时分的日期完整保留', () {
      expect(page.list[1].time, '2026-10-18 20:15');
    });

    test('封面与内容地址补成绝对地址', () {
      expect(
        page.list[0].cover,
        '${Constants.baseUrl}uploadfile/2026/1017/'
        'thumb_362_233_20261017103216427.jpg',
      );
      expect(page.list[0].url, '${Constants.baseUrl}play/d7320/');
      // 已经是绝对地址的封面原样保留.
      expect(
        page.list[1].cover,
        'https://www.tucao.my/uploadfile/2026/1001/cover.jpg',
      );
    });

    test('内容地址区分档案与视频', () {
      expect(page.list[0].target?.article, isTrue);
      expect(page.list[0].target?.hid, '7320');
      expect(page.list[1].target?.article, isFalse);
      expect(page.list[1].target?.hid, '1234');
    });

    test('作者空间地址与 uid', () {
      expect(page.list[0].authorUrl, '${Constants.baseUrl}play/u1/');
      expect(page.list[0].authorId, '1');
      expect(page.list[1].authorId, '42');
    });

    test('没有标题的条目被忽略', () {
      expect(page.list.any((e) => e.content == '没有标题的条目应当被忽略'), isFalse);
    });

    test('分页区有下一页时还有更多', () {
      expect(page.hasMore, isTrue);
    });

    test('空页面返回空列表且没有下一页', () {
      final empty = MessageHttp.parseCommentListHtml('<html></html>');
      expect(empty.list, isEmpty);
      expect(empty.hasMore, isFalse);
      expect(CommentTarget.parse(''), isNull);
    });
  });
}
