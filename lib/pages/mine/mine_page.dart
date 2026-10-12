import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:tucao/build_config.dart';
import 'package:tucao/common/constants.dart';
import 'package:tucao/common/style.dart';
import 'package:tucao/models/user.dart';
import 'package:tucao/router/routes.dart';
import 'package:tucao/services/account_service.dart';
import 'package:tucao/utils/logger.dart';
import 'package:url_launcher/url_launcher.dart';

/// 我的页面.
///
/// 主框架的第四个 tab, 展示账号状态与常用入口.
class MinePage extends StatefulWidget {
  const MinePage({super.key});

  @override
  State<MinePage> createState() => _MinePageState();
}

class _MinePageState extends State<MinePage> {
  String _version = '';
  bool _loggingOut = false;

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) {
        return;
      }
      setState(() {
        // 构建版本由构建时注入, 未注入时退回包版本.
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

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('退出登录'),
        content: const Text('退出后需要重新输入账号密码, 确定退出吗?'),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Get.back(result: true),
            child: const Text('退出'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    setState(() => _loggingOut = true);
    try {
      await AccountService.instance.logout();
      Get.snackbar('已退出登录', '本地登录信息与 cookie 已清除');
    } catch (e, stackTrace) {
      Log.e('退出登录失败', error: e, stackTrace: stackTrace);
      Get.snackbar('退出登录失败', '$e');
    } finally {
      if (mounted) {
        setState(() => _loggingOut = false);
      }
    }
  }

  void _showAbout() {
    showDialog<void>(
      context: context,
      builder: (context) => _AboutDialog(version: _version),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: [
          const Padding(padding: Style.pagePadding, child: _UserHeader()),
          const SizedBox(height: 16),
          ListTile(
            leading: const Icon(Icons.mail_outline),
            title: const Text('私信'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Get.toNamed(Routes.inbox),
          ),
          ListTile(
            leading: const Icon(Icons.history),
            title: const Text('播放历史'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Get.toNamed(Routes.history),
          ),
          ListTile(
            leading: const Icon(Icons.download_outlined),
            title: const Text('离线缓存'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Get.toNamed(Routes.downloads),
          ),
          ListTile(
            leading: const Icon(Icons.article_outlined),
            title: const Text('档案'),
            subtitle: const Text('番组情报与年鉴'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Get.toNamed(Routes.data),
          ),
          ListTile(
            leading: const Icon(Icons.settings_outlined),
            title: const Text('我的设置'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Get.toNamed(Routes.setting),
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('关于'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _showAbout,
          ),
          const SizedBox(height: 16),
          Obx(() {
            if (!AccountService.instance.isLogin) {
              return const SizedBox.shrink();
            }
            return ListTile(
              leading: const Icon(Icons.password_outlined),
              title: const Text('修改密码'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Get.toNamed(Routes.changePassword),
            );
          }),
          Obx(() {
            if (!AccountService.instance.isLogin) {
              return const SizedBox.shrink();
            }
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: OutlinedButton(
                onPressed: _loggingOut ? null : _logout,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(44),
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
                child: _loggingOut
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('退出登录'),
              ),
            );
          }),
        ],
      ),
    );
  }
}

/// 顶部账号卡片, 登录状态变化时自动刷新.
class _UserHeader extends StatelessWidget {
  const _UserHeader();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Obx(() {
      final user = AccountService.instance.user.value;
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              _Avatar(user: user),
              const SizedBox(width: 14),
              Expanded(
                child: user == null
                    ? Text(
                        '未登录, 登录后可同步站点账号信息',
                        style: TextStyle(
                          fontSize: 13,
                          color: scheme.onSurfaceVariant,
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '用户 id: ${user.userId}',
                            style: TextStyle(
                              fontSize: 12,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
              ),
              if (user == null) ...[
                const SizedBox(width: 8),
                FilledButton.tonal(
                  onPressed: () => Get.toNamed(Routes.login),
                  child: const Text('点击登录'),
                ),
              ],
            ],
          ),
        ),
      );
    });
  }
}

/// 圆形头像, 没有头像地址或加载失败时回落到默认图标.
class _Avatar extends StatelessWidget {
  const _Avatar({required this.user});

  static const _size = 56.0;

  final UserModel? user;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final url = user?.avatar ?? '';
    return SizedBox(
      width: _size,
      height: _size,
      child: ClipOval(
        child: url.isEmpty
            ? _placeholder(scheme)
            : CachedNetworkImage(
                imageUrl: url,
                width: _size,
                height: _size,
                fit: BoxFit.cover,
                fadeInDuration: const Duration(milliseconds: 150),
                placeholder: (context, url) => _placeholder(scheme),
                errorWidget: (context, url, error) => _placeholder(scheme),
              ),
      ),
    );
  }

  Widget _placeholder(ColorScheme scheme) {
    return ColoredBox(
      color: scheme.surfaceContainerHighest,
      child: Icon(
        Icons.person,
        size: _size * 0.6,
        color: scheme.onSurfaceVariant,
      ),
    );
  }
}

/// 关于对话框.
class _AboutDialog extends StatelessWidget {
  const _AboutDialog({required this.version});

  final String version;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text(Constants.appName),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            version.isEmpty ? '版本读取中' : '版本 $version',
            style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          _LinkRow(label: '项目地址', url: Constants.sourceCodeUrl),
          const SizedBox(height: 8),
          _LinkRow(label: '参考项目', url: Constants.refererSourceCodeUrl),
          const SizedBox(height: 12),
          Text(
            '本项目是第三方客户端, 与站点官方无关.',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Get.back(), child: const Text('关闭')),
      ],
    );
  }
}

/// 可点击的链接行, 交给系统浏览器打开.
class _LinkRow extends StatelessWidget {
  const _LinkRow({required this.label, required this.url});

  final String label;
  final String url;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$label: ', style: const TextStyle(fontSize: 13)),
        Expanded(
          child: InkWell(
            onTap: () =>
                launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
            child: Text(
              url,
              style: TextStyle(fontSize: 13, color: scheme.primary),
            ),
          ),
        ),
      ],
    );
  }
}
