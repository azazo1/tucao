import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:tucao/http/user_http.dart';
import 'package:tucao/models/form_response.dart';
import 'package:tucao/pages/login/forgot_password_page.dart';
import 'package:tucao/utils/http_util.dart';

/// 所有请求由内存适配器接管, 不请求真实站点或触发邮件发送.
class _Adapter implements HttpClientAdapter {
  FutureOr<ResponseBody> Function(RequestOptions)? respond;
  final requests = <RequestOptions>[];
  final payloads = <String>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    payloads.add(
      requestStream == null
          ? ''
          : await utf8.decoder.bind(requestStream).join(),
    );
    return respond!(options);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  final adapter = _Adapter();
  final cookies = CookieJar();
  final png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Wl6R5sAAAAASUVORK5CYII=',
  );

  ResponseBody image() => ResponseBody.fromBytes(
    png,
    200,
    headers: {
      Headers.contentTypeHeader: ['image/png'],
      'set-cookie': ['PHPSESSID=test-session; Path=/'],
    },
  );

  setUpAll(() {
    HttpUtil.init(cookieInterceptor: CookieManager(cookies));
    HttpUtil.dio.httpClientAdapter = adapter;
  });

  setUp(() async {
    adapter.requests.clear();
    adapter.payloads.clear();
    await cookies.deleteAll();
  });

  group('找回密码提示页解析', () {
    test('真实验证码拒绝页不能判为成功, 样式与脚本不进入提示', () {
      final result = FormResponse.parse(
        File('test/fixtures/forgot_rejected.html').readAsStringSync(),
      );
      expect(result.status, FormResponseStatus.rejected);
      expect(result.message, isNot(contains('setTimeout')));
      expect(result.message, isNot(contains('padding')));
    });

    test('空响应, 表单页面与脚本里的成功标记不构成成功证据', () {
      for (final raw in [
        '',
        '<body><script>var status = "操作成功";</script></body>',
        '<body><form><input name="email"></form>成功</body>',
        '<body>邮件服务暂不可用</body>',
        '<body>发送未成功</body>',
      ]) {
        expect(FormResponse.parse(raw).isSuccess, isFalse);
      }
    });

    test('按官方正文成功标记识别, 不把拒绝结果当作成功', () {
      // 正向结构样本, 不是从真实邮箱发送中取得的成功响应.
      expect(
        FormResponse.parse(
          '<body>操作成功<script>redirect();</script></body>',
        ).status,
        FormResponseStatus.success,
      );
      expect(
        FormResponse.parse(
          '<body><a href="javascript:history.back();">请稍后再试</a></body>',
        ).status,
        FormResponseStatus.rejected,
      );
    });
  });

  group('验证码与提交的请求契约', () {
    test('验证码设置的会话 cookie 被提交复用, 字段按官网表单编码', () async {
      adapter.respond = (options) => options.method == 'GET'
          ? image()
          : ResponseBody.fromString('<body>操作成功</body>', 200);
      expect(await UserHttp.checkCode(), png);
      final result = await UserHttp.forgotPassword(
        email: 'user+tag@example.com',
        code: 'aB12',
      );
      expect(result.isSuccess, isTrue);
      final request = adapter.requests.last;
      expect(request.uri.queryParameters['a'], 'public_forget_password');
      expect(request.method, 'POST');
      expect(
        request.headers[HttpHeaders.cookieHeader],
        contains('PHPSESSID=test-session'),
      );
      expect(Uri.splitQueryString(adapter.payloads.last), {
        'email': 'user+tag@example.com',
        'code': 'aB12',
        'dosubmit': '提交',
      });
    });

    test('刷新验证码绕过缓存, 不复用旧图像', () async {
      adapter.respond = (_) => image();
      await UserHttp.checkCode();
      await UserHttp.checkCode();
      final first = adapter.requests.first;
      final last = adapter.requests.last;
      expect(last.queryParameters['_'], isNot(first.queryParameters['_']));
      expect(last.headers['cache-control'], 'no-cache');
    });

    test('HTML 错误页和空图像不能作为验证码', () async {
      adapter.respond = (_) => ResponseBody.fromString(
        '<body>请重新登录</body>',
        200,
        headers: {
          Headers.contentTypeHeader: ['text/html'],
        },
      );
      await expectLater(UserHttp.checkCode(), throwsFormatException);
      adapter.respond = (_) => ResponseBody.fromBytes(
        [],
        200,
        headers: {
          Headers.contentTypeHeader: ['image/png'],
        },
      );
      await expectLater(UserHttp.checkCode(), throwsFormatException);
    });

    test('HTTP 错误即使带成功正文也不能当作成功', () async {
      adapter.respond = (_) =>
          ResponseBody.fromString('<body>操作成功</body>', 403);
      await expectLater(
        UserHttp.forgotPassword(email: 'test@example.com', code: '1234'),
        throwsA(isA<DioException>()),
      );
    });
  });

  testWidgets('提交期间不能刷新, 离开页面后迟到的成功响应不能再次退栈', (tester) async {
    Get.testMode = true;
    final pending = Completer<ResponseBody>();
    adapter.respond = (options) =>
        options.method == 'GET' ? image() : pending.future;
    await tester.pumpWidget(
      GetMaterialApp(
        home: Scaffold(
          body: TextButton(
            onPressed: () => Get.to(() => const ForgotPasswordPage()),
            child: const Icon(Icons.home),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(TextButton));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextFormField).at(0),
      'test@example.com',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'aB12');
    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    await tester.tap(find.byTooltip('点击换一张'));
    await tester.pump();
    expect(
      adapter.requests.where((request) => request.method == 'GET').length,
      1,
    );
    Get.back();
    await tester.pumpAndSettle();
    pending.complete(ResponseBody.fromString('<body>操作成功</body>', 200));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.home), findsOneWidget);
    expect(find.byType(ForgotPasswordPage), findsNothing);
    expect(Get.isSnackbarOpen, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    Get.reset();
  });

  testWidgets('验证码刷新失败后不能提交旧验证码', (tester) async {
    Get.testMode = true;
    var calls = 0;
    adapter.respond = (_) {
      calls++;
      return calls == 1
          ? image()
          : ResponseBody.fromBytes(
              [],
              200,
              headers: {
                Headers.contentTypeHeader: ['image/png'],
              },
            );
    };
    await tester.pumpWidget(const GetMaterialApp(home: ForgotPasswordPage()));
    await tester.pumpAndSettle();
    var submit = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(submit.onPressed, isNotNull);
    await tester.tap(find.byTooltip('点击换一张'));
    await tester.pumpAndSettle();
    submit = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(submit.onPressed, isNull);
    expect(
      adapter.requests.every((request) => request.method == 'GET'),
      isTrue,
    );
    await tester.pump(const Duration(seconds: 5));
    Get.closeAllSnackbars();
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    Get.reset();
  });
}
