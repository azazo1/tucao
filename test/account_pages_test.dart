import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:tucao/models/user.dart';
import 'package:tucao/pages/login/change_password_page.dart';
import 'package:tucao/pages/login/login_page.dart';
import 'package:tucao/pages/login/register_page.dart';
import 'package:tucao/router/routes.dart';
import 'package:tucao/services/account_service.dart';

/// 用可控的异步操作验证页面生命周期, 不初始化存储或网络.
class _PendingAccount extends GetxController implements AccountService {
  final pending = Completer<void>();
  int calls = 0;

  @override
  final user = Rxn<UserModel>();

  @override
  bool get isLogin => user.value != null;

  @override
  Future<void> refresh() async {}

  @override
  Future<String> login(String username, String password) async {
    calls++;
    await pending.future;
    return '';
  }

  @override
  Future<String> register({
    required String username,
    required String nickname,
    required String email,
    required String password,
    required String confirmPassword,
  }) async {
    calls++;
    await pending.future;
    return '';
  }

  @override
  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
    required String confirmPassword,
  }) async {
    calls++;
    await pending.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final cases = [
    (name: '登录', page: const LoginPage(), values: ['username', 'password']),
    (
      name: '注册',
      page: const RegisterPage(),
      values: [
        'username',
        'nickname',
        'user@example.com',
        'password',
        'password',
      ],
    ),
    (
      name: '修改密码',
      page: const ChangePasswordPage(),
      values: ['old-password', 'new-password', 'new-password'],
    ),
  ];

  testWidgets('修改密码成功后替换为登录页', (tester) async {
    Get.testMode = true;
    final account = _PendingAccount();
    Get.put<AccountService>(account);
    await tester.pumpWidget(
      GetMaterialApp(
        home: const Scaffold(body: Icon(Icons.home)),
        getPages: [GetPage(name: Routes.login, page: () => const LoginPage())],
      ),
    );
    Get.to(() => const ChangePasswordPage());
    await tester.pumpAndSettle();
    final values = ['old-password', 'new-password', 'new-password'];
    for (var i = 0; i < values.length; i++) {
      await tester.enterText(find.byType(TextFormField).at(i), values[i]);
    }
    await tester.ensureVisible(find.byType(FilledButton));
    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    account.pending.complete();
    await tester.pumpAndSettle();
    expect(find.byType(LoginPage), findsOneWidget);
    expect(find.byType(ChangePasswordPage), findsNothing);
    expect(Get.currentRoute, Routes.login);
    await tester.pump(const Duration(seconds: 5));
    Get.closeAllSnackbars();
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    Get.reset();
  });

  for (final item in cases) {
    testWidgets('${item.name}的迟到成功回调不能关闭后来打开的页面', (tester) async {
      Get.testMode = true;
      final account = _PendingAccount();
      Get.put<AccountService>(account);
      await tester.pumpWidget(GetMaterialApp(home: item.page));
      for (var i = 0; i < item.values.length; i++) {
        await tester.enterText(
          find.byType(TextFormField).at(i),
          item.values[i],
        );
      }
      await tester.ensureVisible(find.byType(FilledButton));
      await tester.tap(find.byType(FilledButton));
      await tester.pump();
      expect(account.calls, 1);
      Get.to(() => const Scaffold(body: Icon(Icons.star)));
      await tester.pumpAndSettle();
      account.pending.complete();
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.star), findsOneWidget);
      expect(Get.isSnackbarOpen, isFalse);
      Get.back();
      await tester.pumpAndSettle();
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      Get.reset();
    });
  }
}
