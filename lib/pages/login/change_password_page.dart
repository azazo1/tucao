import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tucao/common/adaptive.dart';
import 'package:tucao/router/routes.dart';
import 'package:tucao/services/account_service.dart';

/// 修改密码页.
///
/// 字段与官方客户端的 changePassword 一致, 需要登录态.
class ChangePasswordPage extends StatefulWidget {
  const ChangePasswordPage({super.key});

  @override
  State<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends State<ChangePasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _oldController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _obscure = true;
  bool _submitting = false;

  @override
  void dispose() {
    _oldController.dispose();
    _newController.dispose();
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
      await AccountService.instance.changePassword(
        oldPassword: _oldController.text,
        newPassword: _newController.text,
        confirmPassword: _confirmController.text,
      );
      if (!_finishSubmission()) {
        return;
      }
      Get.offNamed(Routes.login);
      Get.snackbar('修改成功', '请使用新密码重新登录');
    } catch (e) {
      if (!_finishSubmission()) {
        return;
      }
      Get.snackbar('修改失败', _errorText(e));
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
      appBar: AppBar(title: const Text('修改密码')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: EdgeInsets.fromLTRB(side + 20, 16, side + 20, 24),
            children: [
              TextFormField(
                controller: _oldController,
                obscureText: _obscure,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: '当前密码',
                  prefixIcon: Icon(Icons.lock_outline),
                ),
                validator: (value) =>
                    (value == null || value.isEmpty) ? '请输入当前密码' : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _newController,
                obscureText: _obscure,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: '新密码',
                  prefixIcon: const Icon(Icons.lock_reset_outlined),
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
                    return '请输入新密码';
                  }
                  if (text.length < 6) {
                    return '密码至少 6 位';
                  }
                  if (text == _oldController.text) {
                    return '新密码不能与当前密码相同';
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
                  labelText: '确认新密码',
                  prefixIcon: Icon(Icons.lock_reset_outlined),
                ),
                validator: (value) =>
                    value != _newController.text ? '两次输入的新密码不一致' : null,
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
                    : const Text('确认修改'),
              ),
              const SizedBox(height: 16),
              Text(
                '修改成功后应用会清除保存的登录态, 请使用新密码重新登录.',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
