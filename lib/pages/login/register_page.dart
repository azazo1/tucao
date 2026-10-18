import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tucao/common/adaptive.dart';
import 'package:tucao/services/account_service.dart';

/// 注册页.
///
/// 字段与站点注册表单一致. 注册成功后站点会自动登录, 因此这里直接回到上一页.
class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _nicknameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _obscure = true;
  bool _submitting = false;

  @override
  void dispose() {
    _usernameController.dispose();
    _nicknameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting || !(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _submitting = true);
    try {
      await AccountService.instance.register(
        username: _usernameController.text.trim(),
        nickname: _nicknameController.text.trim(),
        email: _emailController.text.trim(),
        password: _passwordController.text,
        confirmPassword: _confirmController.text,
      );
      if (!_finishSubmission()) {
        return;
      }
      Get.back();
      Get.snackbar('注册成功', '已自动登录');
    } catch (e) {
      if (!_finishSubmission()) {
        return;
      }
      Get.snackbar('注册失败', _errorText(e));
    }
  }

  bool _finishSubmission() {
    if (!mounted) {
      return false;
    }
    setState(() => _submitting = false);
    return ModalRoute.of(context)?.isCurrent ?? false;
  }

  String _errorText(Object error) {
    if (error is DioException) {
      if (error.type == DioExceptionType.connectionError) {
        return '网络连接失败, 请检查网络';
      }
      if (error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.receiveTimeout) {
        return '网络超时, 请稍后重试';
      }
    }
    final message = error is Exception ? error.toString() : '$error';
    return message.replaceFirst('Exception: ', '');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // 表单在宽屏下收窄居中, 输入框不横跨整个屏幕.
    final side = Adaptive.sidePadding(
      context,
      maxWidth: Adaptive.formMaxWidth,
    );
    return Scaffold(
      appBar: AppBar(title: const Text('注册')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: EdgeInsets.fromLTRB(side + 20, 16, side + 20, 24),
            children: [
              TextFormField(
                controller: _usernameController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: '用户名',
                  helperText: '登录用, 注册后不可更改',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                validator: (value) {
                  final text = value?.trim() ?? '';
                  if (text.isEmpty) {
                    return '请输入用户名';
                  }
                  if (text.length < 3) {
                    return '用户名至少 3 个字符';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _nicknameController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: '昵称',
                  helperText: '站内展示的名字',
                  prefixIcon: Icon(Icons.badge_outlined),
                ),
                validator: (value) =>
                    (value == null || value.trim().isEmpty) ? '请输入昵称' : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _emailController,
                textInputAction: TextInputAction.next,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: '邮箱',
                  prefixIcon: Icon(Icons.mail_outline),
                ),
                validator: (value) {
                  final text = value?.trim() ?? '';
                  if (text.isEmpty) {
                    return '请输入邮箱';
                  }
                  if (!text.contains('@') || !text.contains('.')) {
                    return '邮箱格式不正确';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _passwordController,
                obscureText: _obscure,
                textInputAction: TextInputAction.next,
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
                validator: (value) {
                  final text = value ?? '';
                  if (text.isEmpty) {
                    return '请输入密码';
                  }
                  if (text.length < 6) {
                    return '密码至少 6 位';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _confirmController,
                obscureText: _obscure,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: '确认密码',
                  prefixIcon: Icon(Icons.lock_reset_outlined),
                ),
                validator: (value) =>
                    value != _passwordController.text ? '两次输入的密码不一致' : null,
                onFieldSubmitted: (_) => _submit(),
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
                    : const Text('注册'),
              ),
              const SizedBox(height: 16),
              Text(
                '注册会直接提交到吐槽站点, 本项目不保存账号密码, '
                '登录态仅保留站点下发的 cookie.',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
