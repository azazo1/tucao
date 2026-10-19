import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tucao/http/api_path.dart';
import 'package:tucao/http/reply_http.dart';
import 'package:tucao/utils/http_util.dart';
import 'package:tucao/models/reply.dart';

/// 评论接口的 id 构造与响应解析测试.
///
/// 样本取自站点真实响应. 这两处都曾经出错:
/// - commentid 末尾的 1 是固定值, 不是分P序号, 多带分P后缀时接口返回 0.
/// - data 是以评论 id 为键的对象, 不是数组.
void main() {
  group('评论楼层 id', () {
    test('构造与站点一致, 不带分P后缀', () {
      expect(ApiPath.commentId(11, '4107869'), 'content_11-4107869-1');
    });

    test('分区号参与构造', () {
      expect(ApiPath.commentId(24, '123'), 'content_24-123-1');
    });
  });

  group('弹幕播放器 id', () {
    test('构造与站点一致, 末尾是分P序号', () {
      expect(ApiPath.playerId(11, '4107869', 0), '11-4107869-1-0');
      expect(ApiPath.playerId(11, '4107869', 1), '11-4107869-1-1');
    });
  });

  group('评论响应解析', () {
    late ReplyPage page;

    setUpAll(() {
      final raw = File('test/fixtures/reply_real.json').readAsStringSync();
      page = ReplyPage.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    });

    test('data 为对象时按值取评论', () {
      expect(page.list, hasLength(2));
      expect(page.title, isNotEmpty);
    });

    test('总数取站点给出的 total', () {
      // total 是字符串, 且比本页条数多.
      expect(page.total, 3);
    });

    test('评论字段解析正确', () {
      final first = page.list.first;
      expect(first.id, '316510');
      expect(first.commentId, 'content_11-4107869-1');
      expect(first.userId, 453580);
      expect(first.userName, '樱影菊忌');
      expect(first.content, contains('文库'));
      expect(first.createAt, '2026-10-05 12:25:05');
      expect(first.avatar, startsWith('http'));
    });

    test('data 为空对象时返回空列表', () {
      final empty = ReplyPage.fromJson({
        'total': '0',
        'data': <String, dynamic>{},
      });
      expect(empty.list, isEmpty);
      expect(empty.total, 0);
    });
  });

  group('发送评论的参数位置', () {
    RequestOptions? captured;

    setUpAll(() {
      // dio 只能初始化一次, 拦截器也只挂一次.
      HttpUtil.init();
      // 拦下请求, 只记录参数形状, 不真的发出.
      HttpUtil.dio.interceptors.insert(
        0,
        InterceptorsWrapper(
          onRequest: (options, handler) {
            captured = options;
            handler.reject(
              DioException(requestOptions: options, message: 'captured'),
              true,
            );
          },
        ),
      );
    });

    setUp(() => captured = null);

    test('commentid 与 id 是查询参数, content 是表单字段', () async {
      await expectLater(
        ReplyHttp.send(
          typeId: 11,
          hid: '4107869',
          content: '你好',
          replyId: 316510,
          replyUid: 453580,
        ),
        throwsA(isA<DioException>()),
      );

      final options = captured!;
      expect(options.queryParameters['commentid'], 'content_11-4107869-1');
      expect(options.queryParameters['id'], 316510);
      expect(options.queryParameters['replyuid'], 453580);
      expect(options.data, {'content': '你好'});
      // 这些不能出现在表单里, 站点会判为非法参数.
      expect((options.data as Map).containsKey('commentid'), isFalse);
      expect((options.data as Map).containsKey('replyid'), isFalse);
    });

    test('发顶层评论时不带 id 与 replyuid', () async {
      await expectLater(
        ReplyHttp.send(typeId: 11, hid: '4107869', content: '顶层评论'),
        throwsA(isA<DioException>()),
      );

      final options = captured!;
      expect(options.queryParameters['commentid'], 'content_11-4107869-1');
      expect(options.queryParameters.containsKey('id'), isFalse);
      expect(options.queryParameters.containsKey('replyuid'), isFalse);
      expect(options.data, {'content': '顶层评论'});
    });
  });

  group('拉取评论的参数', () {
    RequestOptions? captured;

    setUpAll(() {
      // 复用上面已经初始化好的 dio, 只补挂一个拦截器.
      HttpUtil.dio.interceptors.insert(
        0,
        InterceptorsWrapper(
          onRequest: (options, handler) {
            captured = options;
            handler.reject(
              DioException(requestOptions: options, message: 'captured'),
              true,
            );
          },
        ),
      );
    });

    setUp(() => captured = null);

    test('只带官方定义的参数', () async {
      await expectLater(
        ReplyHttp.list(typeId: 11, hid: '4107869', page: 2, pageSize: 20),
        throwsA(isA<DioException>()),
      );
      final options = captured!;
      expect(options.queryParameters.keys.toSet(), {
        'commentid',
        'page',
        'num',
      });
      expect(options.queryParameters['commentid'], 'content_11-4107869-1');
      expect(options.queryParameters['page'], 2);
      expect(options.queryParameters['num'], 20);
      // hot 是站点忽略的参数, 不应出现.
      expect(options.queryParameters.containsKey('hot'), isFalse);
    });

    test('楼中楼只多带 replyid', () async {
      await expectLater(
        ReplyHttp.list(
          typeId: 11,
          hid: '4107869',
          page: 1,
          pageSize: 20,
          replyId: 316510,
        ),
        throwsA(isA<DioException>()),
      );
      final options = captured!;
      expect(options.queryParameters.keys.toSet(), {
        'commentid',
        'replyid',
        'page',
        'num',
      });
      expect(options.queryParameters['replyid'], 316510);
    });
  });

  group('上传图评的参数位置', () {
    RequestOptions? captured;

    setUpAll(() {
      HttpUtil.dio.interceptors.insert(
        0,
        InterceptorsWrapper(
          onRequest: (options, handler) {
            captured = options;
            handler.reject(
              DioException(requestOptions: options, message: 'captured'),
              true,
            );
          },
        ),
      );
    });

    setUp(() => captured = null);

    test('commentid 是查询参数, 图片放在 file 字段', () async {
      await expectLater(
        ReplyHttp.uploadImage(
          typeId: 11,
          hid: '4107869',
          fileName: 'shot.png',
          bytes: const [1, 2, 3],
        ),
        throwsA(isA<DioException>()),
      );

      final options = captured!;
      expect(options.queryParameters, {'commentid': 'content_11-4107869-1'});
      final data = options.data as FormData;
      expect(data.fields, isEmpty);
      expect(data.files, hasLength(1));
      expect(data.files.single.key, 'file');
      // 原名只用来取后缀, 其余换成 ASCII 与时间戳.
      expect(
        data.files.single.value.filename,
        matches(RegExp(r'^tucao_\d+\.png$')),
      );
    });

    test('上传文件名只保留后缀', () {
      expect(ReplyHttp.uploadFileName('截图 1.PNG'), matches(RegExp(r'\.png$')));
      expect(ReplyHttp.uploadFileName('noext'), matches(RegExp(r'\.jpg$')));
    });

    test('成功时返回站点片段', () {
      const raw = '{"status":1,"bbcode":"[img]https://a/b.png[/img]"}';
      expect(ReplyHttp.parseUploadResponse(raw), '[img]https://a/b.png[/img]');
    });

    test('status 是字符串时也按成功处理', () {
      expect(ReplyHttp.parseUploadResponse('{"status":"1","bbcode":"x"}'), 'x');
    });

    test('失败时抛出站点给出的提示', () {
      expect(
        () => ReplyHttp.parseUploadResponse('{"status":0,"msg":"只有破会员才能发图评"}'),
        throwsA(
          predicate((e) => e.toString().contains('只有破会员才能发图评'), '带站点提示的异常'),
        ),
      );
    });

    test('成功但缺少片段时抛格式错误', () {
      expect(
        () => ReplyHttp.parseUploadResponse('{"status":1}'),
        throwsA(isA<FormatException>()),
      );
    });

    test('会话过期的 html 页面提示重新登录', () {
      expect(
        () => ReplyHttp.parseUploadResponse(
          '<html><body><a>您的会话已过期，请重新登录。</a></body></html>',
        ),
        throwsA(predicate((e) => e.toString().contains('登录已失效'), '登录失效提示')),
      );
    });

    test('无法识别的内容给出上传失败提示', () {
      expect(
        () => ReplyHttp.parseUploadResponse('0'),
        throwsA(predicate((e) => e.toString().contains('图片上传失败'), '上传失败提示')),
      );
    });
  });
}
