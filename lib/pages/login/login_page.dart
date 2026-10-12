import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tucao/router/routes.dart';
import 'package:tucao/services/account_service.dart';

/// 登录页.
///
/// 站点是 discuz 表单登录, 登录态由 cookie 维持, 本地不保存密码.
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordFocus = FocusNode();

  bool _obscure = true;
  bool _submitting = false;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting || !(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _submitting = true);
    try {
      await AccountService.instance.login(
        _usernameController.text.trim(),
        _passwordController.text,
      );
      if (!_finishSubmission()) {
        return;
      }
      Get.back();
      Get.snackbar(
        '登录成功',
        '欢迎回来, ${AccountService.instance.user.value?.displayName ?? ''}',
      );
    } catch (e) {
      if (!_finishSubmission()) {
        return;
      }
      Get.snackbar('登录失败', _errorText(e));
    }
  }

  bool _finishSubmission() {
    if (!mounted) {
      return false;
    }
    setState(() => _submitting = false);
    return ModalRoute.of(context)?.isCurrent ?? false;
  }

  /// 网络异常与业务异常分开提示, 保证任何情况下都有可读的错误信息.
  String _errorText(Object error) {
    if (error is DioException) {
      if (error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.receiveTimeout ||
          error.type == DioExceptionType.sendTimeout) {
        return '网络超时, 请稍后重试';
      }
      if (error.type == DioExceptionType.connectionError) {
        return '网络连接失败, 请检查网络';
      }
      return '请求失败: ${error.message ?? error.type.name}';
    }
    final message = error is Exception ? error.toString() : '$error';
    return message.replaceFirst('Exception: ', '');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('登录')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            children: [
              TextFormField(
                controller: _usernameController,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.username],
                decoration: const InputDecoration(
                  labelText: '用户名',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                validator: (value) =>
                    (value == null || value.trim().isEmpty) ? '请输入用户名' : null,
                onFieldSubmitted: (_) => _passwordFocus.requestFocus(),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _passwordController,
                focusNode: _passwordFocus,
                obscureText: _obscure,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.password],
                decoration: InputDecoration(
                  labelText: '密码',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                    ),
                    tooltip: _obscure ? '显示密码' : '隐藏密码',
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
                validator: (value) =>
                    (value == null || value.isEmpty) ? '请输入密码' : null,
                onFieldSubmitted: (_) => _submit(),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _submitting
                      ? null
                      : () => Get.toNamed(Routes.forgotPassword),
                  child: const Text('忘记密码'),
                ),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _submitting ? null : _submit,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(44),
                ),
                child: _submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('登录'),
              ),
              const SizedBox(height: 24),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      '登录即表示使用站点账号, 本项目不保存密码.',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _submitting ? null : () => Get.toNamed(Routes.register),
                    child: const Text('注册账号'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
