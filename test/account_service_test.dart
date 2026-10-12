import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:tucao/http/init.dart';
import 'package:tucao/models/user.dart';
import 'package:tucao/services/account_service.dart';
import 'package:tucao/utils/http_util.dart';
import 'package:tucao/utils/storage.dart';

class _AccountBox implements Box {
  final data = <dynamic, dynamic>{};

  @override
  dynamic get(dynamic key, {dynamic defaultValue}) => data[key] ?? defaultValue;

  @override
  Future<void> put(dynamic key, dynamic value) async => data[key] = value;

  @override
  Future<void> delete(dynamic key) async => data.remove(key);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Cookies implements PersistCookieJar {
  int clears = 0;

  @override
  Future<void> deleteAll() async => clears++;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 响应完全在内存中构造, 不向真实账号发出注册或改密请求.
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
    payloads.add(requestStream == null ? '' : await utf8.decoder.bind(requestStream).join());
    return respond!(options);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  final adapter = _Adapter();
  late AccountService account;
  late _AccountBox box;
  late _Cookies cookies;
  const cached = UserModel(userId: 1, userName: 'cached-user');

  ResponseBody info() => ResponseBody.fromString(
    '{"islogin":true,"userid":2,"username":"current-user"}',
    200,
  );
  ResponseBody success() => ResponseBody.fromString('<body>操作成功</body>', 200);

  Future<void> changePassword() => account.changePassword(
    oldPassword: 'old-password',
    newPassword: 'new-password',
    confirmPassword: 'new-password',
  );

  setUpAll(() {
    HttpUtil.init();
    HttpUtil.dio.httpClientAdapter = adapter;
  });

  setUp(() {
    adapter.requests.clear();
    adapter.payloads.clear();
    box = _AccountBox();
    cookies = _Cookies();
    GStorage.account = box;
    HttpInit.cookieJar = cookies;
    account = AccountService();
    account.user.value = cached;
    box.data['user'] = cached.toJson();
  });

  test('修改密码只有明确成功后才清空本地用户与 cookie', () async {
    adapter.respond = (_) => success();
    await changePassword();
    expect(account.isLogin, isFalse);
    expect(box.data.containsKey('user'), isFalse);
    expect(cookies.clears, 1);
    expect(adapter.requests.single.uri.queryParameters['a'], 'account_manage_password');
    expect(Uri.splitQueryString(adapter.payloads.single), {
      'info[password]': 'old-password',
      'info[newpassword]': 'new-password',
      'info[renewpassword]': 'new-password',
      'dosubmit': '提交',
    });
  });

  test('未知响应与 HTTP 拒绝不能清空账号或假装改密成功', () async {
    for (final response in [
      ResponseBody.fromString('', 200),
      ResponseBody.fromString('<body>请稍后重试</body>', 200),
      ResponseBody.fromString('<body>操作成功</body>', 403),
    ]) {
      adapter.respond = (_) => response;
      await expectLater(changePassword(), throwsA(isA<Exception>()));
      expect(account.user.value, cached);
      expect(box.data['user'], cached.toJson());
      expect(cookies.clears, 0);
    }
  });

  test('改密前尚未完成的状态查询不能恢复已清空的用户', () async {
    final queried = Completer<void>();
    final pending = Completer<ResponseBody>();
    adapter.respond = (request) {
      if (request.uri.queryParameters['op'] == 'user') {
        queried.complete();
        return pending.future;
      }
      return success();
    };
    final refreshing = account.refresh();
    await queried.future;
    await changePassword();
    pending.complete(info());
    await refreshing;
    expect(account.isLogin, isFalse);
    expect(box.data.containsKey('user'), isFalse);
  });

  test('服务端确认失败时不能用旧缓存宣称登录成功', () async {
    adapter.respond = (request) => request.method == 'POST'
        ? success()
        : ResponseBody.fromString('unavailable', 503);
    await expectLater(account.login('current-user', 'password'), throwsA(isA<DioException>()));
    expect(adapter.requests.length, 2);
    expect(account.user.value, cached);
  });

  test('服务端确认未登录时清空旧账号, 注册不能假装自动登录成功', () async {
    adapter.respond = (request) => request.method == 'POST'
        ? success()
        : ResponseBody.fromString('{"islogin":false}', 200);
    await expectLater(
      account.register(
        username: 'current-user',
        nickname: 'nickname',
        email: 'user@example.com',
        password: 'password',
        confirmPassword: 'password',
      ),
      throwsA(isA<Exception>()),
    );
    expect(account.isLogin, isFalse);
    expect(box.data.containsKey('user'), isFalse);
  });

  test('登录缓存只保存本次确认的用户信息, 不保存密码', () async {
    adapter.respond = (request) => request.method == 'POST' ? success() : info();
    await account.login('current-user', 'password');
    expect(account.user.value?.userId, 2);
    expect((box.data['user'] as Map)['userid'], 2);
    expect((box.data['user'] as Map).containsKey('password'), isFalse);
  });
}
