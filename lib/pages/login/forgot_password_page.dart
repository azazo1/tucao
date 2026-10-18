import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tucao/common/adaptive.dart';
import 'package:tucao/http/user_http.dart';

/// 找回密码页.
///
/// 站点只要求邮箱与图形验证码, 校验通过后把新密码发到邮箱.
/// 验证码与提交必须共用同一份 cookie, 因此这里不新建 dio 实例.
class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _codeController = TextEditingController();
  final _cancelToken = CancelToken();

  Uint8List? _codeImage;
  bool _loadingCode = false;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _refreshCode();
  }

  @override
  void dispose() {
    _cancelToken.cancel();
    _emailController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _refreshCode() async {
    if (_loadingCode || _submitting) {
      return;
    }
    _codeController.clear();
    setState(() {
      _loadingCode = true;
      _codeImage = null;
    });
    try {
      final bytes = await UserHttp.checkCode(cancelToken: _cancelToken);
      if (!mounted) {
        return;
      }
      setState(() {
        _codeImage = Uint8List.fromList(bytes);
        _loadingCode = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() => _loadingCode = false);
      Get.snackbar('验证码加载失败', _errorText(e));
    }
  }

  Future<void> _submit() async {
    if (_submitting ||
        _loadingCode ||
        _codeImage == null ||
        !(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _submitting = true);
    try {
      final result = await UserHttp.forgotPassword(
        email: _emailController.text.trim(),
        code: _codeController.text.trim(),
        cancelToken: _cancelToken,
      );
      if (!mounted) {
        return;
      }
      if (!result.isSuccess) {
        setState(() => _submitting = false);
        Get.snackbar('提交未成功', result.message);
        await _refreshCode();
        return;
      }
      Get.back();
      Get.snackbar('提交成功', result.message);
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() => _submitting = false);
      Get.snackbar('提交失败', _errorText(e));
      await _refreshCode();
    }
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
      appBar: AppBar(title: const Text('找回密码')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: EdgeInsets.fromLTRB(side + 20, 16, side + 20, 24),
            children: [
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: '注册邮箱',
                  prefixIcon: Icon(Icons.mail_outline),
                ),
                validator: (value) {
                  final text = value?.trim() ?? '';
                  if (text.isEmpty) {
                    return '请输入邮箱';
                  }
                  if (!text.contains('@')) {
                    return '邮箱格式不正确';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _codeController,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  labelText: '验证码',
                  prefixIcon: const Icon(Icons.verified_outlined),
                  suffixIcon: _codeSlot(),
                ),
                validator: (value) =>
                    (value == null || value.trim().isEmpty) ? '请输入验证码' : null,
                onFieldSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _submitting || _loadingCode || _codeImage == null
                    ? null
                    : _submit,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(44),
                ),
                child: _submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('提交'),
              ),
              const SizedBox(height: 16),
              Text(
                '验证通过后站点会把新密码发到该邮箱, 请及时修改.',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 验证码图片, 点击可以换一张.
  Widget _codeSlot() {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        onTap: _loadingCode || _submitting ? null : _refreshCode,
        borderRadius: BorderRadius.circular(6),
        child: Tooltip(
          message: '点击换一张',
          child: SizedBox(
            width: 96,
            height: 48,
            child: _codeImage == null
                ? Center(
                    child: _loadingCode
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh, size: 18),
                  )
                : Image.memory(
                    _codeImage!,
                    fit: BoxFit.contain,
                    gaplessPlayback: true,
                  ),
          ),
        ),
      ),
    );
  }
}
