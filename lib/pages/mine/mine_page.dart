import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:tucao/build_config.dart';
import 'package:tucao/common/adaptive.dart';
import 'package:tucao/common/constants.dart';
import 'package:tucao/common/style.dart';
import 'package:tucao/common/vip.dart';
import 'package:tucao/models/user.dart';
import 'package:tucao/router/routes.dart';
import 'package:tucao/services/account_service.dart';
import 'package:tucao/services/update_service.dart';
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

  void _showAbout() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => _AboutDialog(
        version: _version,
        onCheckUpdate: () {
          Navigator.pop(dialogContext);
          unawaited(_checkUpdate());
        },
      ),
    );
  }

  /// 手动检查更新, 关于对话框关闭后调用, 因此可以正常弹出提示.
  Future<void> _checkUpdate() async {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('正在检查更新...'), duration: Duration(seconds: 2)),
    );
    await UpdateService.checkManually(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: ListView(
        padding: EdgeInsets.symmetric(
          horizontal: Adaptive.sidePadding(context),
          vertical: 12,
        ),
        children: [
          const Padding(padding: Style.pagePadding, child: _UserHeader()),
          const _VipCard(),
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
            leading: const Icon(Icons.star_outline),
            title: const Text('本地收藏'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Get.toNamed(Routes.favorites),
          ),
          ListTile(
            leading: const Icon(Icons.download_outlined),
            title: const Text('离线缓存'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Get.toNamed(Routes.downloads),
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
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: user == null
              ? null
              : () => Get.toNamed(
                  Routes.space,
                  parameters: {'uid': user.userId.toString()},
                ),
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
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                // 破会员的昵称与网页端一样用站点金色.
                                color: user.isVip ? Vip.nicknameColor : null,
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
                ] else
                  Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
      );
    });
  }
}

/// 破会员身份卡.
///
/// 会员身份来自站点 `api.php?op=user` 的 vip 字段, 非会员时整块不显示.
class _VipCard extends StatelessWidget {
  const _VipCard();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Obx(() {
      final user = AccountService.instance.user.value;
      if (user == null || !user.isVip) {
        return const SizedBox.shrink();
      }
      return Padding(
        padding: Style.pagePadding,
        child: Card(
          color: Vip.nicknameColor.withValues(alpha: 0.1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: Vip.nicknameColor.withValues(alpha: 0.4),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Icon(Icons.workspace_premium, color: Vip.nicknameColor),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '破会员',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Vip.nicknameColor,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '站点会员头衔, 昵称在评论区显示金色. 特权: 无广告, 亮眼, 图评.',
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
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
  const _AboutDialog({required this.version, required this.onCheckUpdate});

  final String version;
  final VoidCallback onCheckUpdate;

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
          const Text('参考项目', style: TextStyle(fontSize: 13)),
          const SizedBox(height: 4),
          _LinkRow(label: 'Tucao', url: Constants.refererSourceCodeUrl),
          const SizedBox(height: 8),
          _LinkRow(label: 'PiliPlus', url: Constants.piliPlusUrl),
          const SizedBox(height: 8),
          _LinkRow(label: '吐槽官网', url: Constants.officialSiteUrl),
          const SizedBox(height: 12),
          Text(
            '本项目是第三方客户端, 与站点官方无关.',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: onCheckUpdate, child: const Text('检查更新')),
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
