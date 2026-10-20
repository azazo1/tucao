import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:tucao/build_config.dart';
import 'package:tucao/common/adaptive.dart';
import 'package:tucao/common/constants.dart';
import 'package:tucao/http/message_http.dart';
import 'package:tucao/router/routes.dart';
import 'package:tucao/services/account_service.dart';
import 'package:tucao/utils/logger.dart';

/// 反馈页.
///
/// 反馈通过站点私信发给开发者 [Constants.developerUid], 不经过第三方服务.
/// 发送需要登录态; 正文之外只附上应用版本与系统版本, 方便对照问题.
class FeedbackPage extends StatefulWidget {
  const FeedbackPage({super.key});

  /// 私信标题, 与普通私信的 "你好" 区分开.
  static const subject = '客户端反馈';

  /// 正文最多字数. 站点私信正文另有上限, 这里留出页脚的位置.
  static const maxLength = 400;

  @override
  State<FeedbackPage> createState() => _FeedbackPageState();
}

class _FeedbackPageState extends State<FeedbackPage> {
  final _controller = TextEditingController();

  /// 正在提交, 防止连点发出两条.
  bool _sending = false;

  /// 本地校验或站点给的失败提示, 留在页面里显示.
  String? _error;

  /// 应用版本, 读取失败时为空.
  String _version = '';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 版本号优先取构建时注入的值, 与关于对话框显示的一致.
  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) {
        return;
      }
      setState(() {
        _version = BuildConfig.buildVersion == 'dev-build'
            ? (info.buildNumber.isEmpty
                  ? info.version
                  : '${info.version}+${info.buildNumber}')
            : BuildConfig.buildVersion;
      });
    } catch (e) {
      Log.w('读取版本号失败: $e');
    }
  }

  /// 拼出发送出去的正文.
  ///
  /// 页脚只写版本, 不写账号或其他能定位到人的信息.
  static String composeContent({
    required String text,
    required String version,
  }) {
    final os = Platform.operatingSystem;
    final osVersion = Platform.operatingSystemVersion
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final system = osVersion.isEmpty ? os : '$os $osVersion';
    return '$text\n\n---\n应用版本: ${version.isEmpty ? '未知' : version}'
        '\n系统: $system';
  }

  Future<void> _submit() async {
    final text = _controller.text.trim();
    if (_sending) {
      return;
    }
    if (text.isEmpty) {
      setState(() => _error = '请先输入反馈内容');
      return;
    }
    if (!AccountService.instance.isLogin) {
      setState(() => _error = '请先登录后再发送反馈');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _sending = true;
      _error = null;
    });
    var sent = false;
    try {
      final result = await MessageHttp.send(
        toUser: Constants.developerUid,
        subject: FeedbackPage.subject,
        content: composeContent(text: text, version: _version),
      );
      if (!mounted) {
        return;
      }
      if (result != null) {
        setState(() => _error = result);
        return;
      }
      // 结果交给入口页, 由那边在页面关掉后给出提示.
      sent = true;
      Get.back(result: true);
    } catch (e, stackTrace) {
      Log.e('发送反馈失败', error: e, stackTrace: stackTrace);
      if (mounted) {
        setState(() => _error = '发送失败, 请稍后重试');
      }
    } finally {
      // 发送成功后页面已经关掉, 不再更新状态.
      if (mounted && !sent) {
        setState(() => _sending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // 表单在宽屏下收窄居中, 与登录一类的文字页保持一致.
    final side = Adaptive.sidePadding(context, maxWidth: Adaptive.formMaxWidth);
    return Scaffold(
      appBar: AppBar(title: const Text('向开发者反馈')),
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.fromLTRB(side + 20, 12, side + 20, 24),
          children: [
            Text(
              '反馈会以站点私信发给开发者 (u${Constants.developerUid}), '
              '不会公开显示.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '发送时会附带应用版本与系统版本, 方便对照问题.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),
            Obx(() {
              if (AccountService.instance.isLogin) {
                return const SizedBox.shrink();
              }
              return _LoginHint(onLogin: () => Get.toNamed(Routes.login));
            }),
            TextField(
              controller: _controller,
              minLines: 6,
              maxLines: 12,
              maxLength: FeedbackPage.maxLength,
              textInputAction: TextInputAction.newline,
              decoration: const InputDecoration(
                hintText: '遇到的问题, 想要的功能, 或者对界面的建议',
                border: OutlineInputBorder(),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  _error!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.error,
                  ),
                ),
              ),
            const SizedBox(height: 10),
            Obx(() {
              final enabled = AccountService.instance.isLogin && !_sending;
              return FilledButton.icon(
                onPressed: enabled ? _submit : null,
                icon: _sending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_outlined, size: 18),
                label: Text(_sending ? '发送中...' : '发送反馈'),
              );
            }),
          ],
        ),
      ),
    );
  }
}

/// 未登录时的提示卡片, 点按钮去登录, 登录成功后回到本页.
class _LoginHint extends StatelessWidget {
  const _LoginHint({required this.onLogin});

  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      color: scheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '发送反馈需要先登录站点账号.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSecondaryContainer,
                ),
              ),
            ),
            TextButton(
              onPressed: onLogin,
              style: TextButton.styleFrom(
                foregroundColor: scheme.onSecondaryContainer,
              ),
              child: const Text('去登录'),
            ),
          ],
        ),
      ),
    );
  }
}
