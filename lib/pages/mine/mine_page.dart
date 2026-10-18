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
import 'package:tucao/http/space_http.dart';
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
      const SnackBar(
        content: Text('正在检查更新...'),
        duration: Duration(seconds: 2),
      ),
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
///
/// 头像与横幅取自自己的用户空间页: 那个页面应用本来就会访问, 不受站点网页版
/// 会员中心的影响. 有横幅就把它铺在卡片顶部, 没有就退回主题色渐变.
/// 点卡片进自己的用户空间, 点头像或横幅则是放大查看, 放大后长按可保存.
class _UserHeader extends StatefulWidget {
  const _UserHeader();

  @override
  State<_UserHeader> createState() => _UserHeaderState();
}

class _UserHeaderState extends State<_UserHeader> {
  static const _bannerHeight = 104.0;
  static const _avatarSize = 56.0;

  Worker? _userWorker;

  /// 自己的用户空间资料, 用来取头像与横幅.
  SpaceInfo? _info;

  /// 已经为哪个 uid 取过资料, 避免重复请求.
  int _loadedUserId = 0;

  @override
  void initState() {
    super.initState();
    _userWorker = ever<UserModel?>(AccountService.instance.user, (user) {
      if (user == null) {
        setState(() {
          _info = null;
          _loadedUserId = 0;
        });
        return;
      }
      unawaited(_loadSpace(user.userId));
    });
    final current = AccountService.instance.user.value;
    if (current != null) {
      unawaited(_loadSpace(current.userId));
    }
  }

  @override
  void dispose() {
    _userWorker?.dispose();
    super.dispose();
  }

  Future<void> _loadSpace(int userId) async {
    if (_loadedUserId == userId) {
      return;
    }
    _loadedUserId = userId;
    try {
      final page = await SpaceHttp.fetch(userId: userId);
      if (!mounted || AccountService.instance.user.value?.userId != userId) {
        return;
      }
      setState(() => _info = page.info);
    } catch (e, stackTrace) {
      Log.e('读取自己的用户空间失败', error: e, stackTrace: stackTrace);
      // 允许下次进页面时重试.
      _loadedUserId = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Obx(() {
      final user = AccountService.instance.user.value;
      if (user == null) {
        return _buildGuest(context, scheme);
      }
      return _buildUser(context, scheme, user);
    });
  }

  Widget _buildGuest(BuildContext context, ColorScheme scheme) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            _placeholderAvatar(scheme),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                '未登录, 登录后可同步站点账号信息',
                style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonal(
              onPressed: () => Get.toNamed(Routes.login),
              child: const Text('点击登录'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUser(BuildContext context, ColorScheme scheme, UserModel user) {
    final banner = _info?.banner ?? '';
    final avatar = (_info?.avatar.isNotEmpty ?? false)
        ? _info!.avatar
        : user.avatar;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Get.toNamed(
          Routes.space,
          parameters: {'uid': user.userId.toString()},
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: _bannerHeight + _avatarSize / 2,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    height: _bannerHeight,
                    child: _buildBanner(scheme, banner),
                  ),
                  Positioned(
                    left: 14,
                    top: _bannerHeight - _avatarSize / 2,
                    child: _buildAvatar(scheme, avatar),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                user.displayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  // 破会员的昵称与网页端一样用站点金色.
                                  color: user.isVip
                                      ? Vip.nicknameColor
                                      : null,
                                ),
                              ),
                            ),
                            if (user.isVip) ...[
                              const SizedBox(width: 6),
                              const VipBadge(),
                            ],
                          ],
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
                  Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 没有横幅时的底色: 用主题容器色拼一层渐变.
  Widget _bannerBackground(ColorScheme scheme) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primaryContainer.withValues(alpha: 0.9),
            scheme.secondaryContainer.withValues(alpha: 0.9),
          ],
        ),
      ),
    );
  }

  Widget _buildBanner(ColorScheme scheme, String banner) {
    final placeholder = _bannerBackground(scheme);
    if (banner.isEmpty) {
      return placeholder;
    }
    return CachedNetworkImage(
      imageUrl: banner,
      fit: BoxFit.cover,
      placeholder: (context, url) => placeholder,
      errorWidget: (context, url, error) => placeholder,
    );
  }

  Widget _buildAvatar(ColorScheme scheme, String avatar) {
    final image = avatar.isEmpty
        ? _placeholderAvatar(scheme)
        : CachedNetworkImage(
            imageUrl: avatar,
            width: _avatarSize,
            height: _avatarSize,
            fit: BoxFit.cover,
            fadeInDuration: const Duration(milliseconds: 150),
            placeholder: (context, url) => _placeholderAvatar(scheme),
            errorWidget: (context, url, error) => _placeholderAvatar(scheme),
          );
    return Container(
      width: _avatarSize,
      height: _avatarSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        // 头像压在横幅上, 加一圈描边避免糊在一起.
        border: Border.all(color: scheme.surface, width: 2),
      ),
      child: ClipOval(child: image),
    );
  }

  Widget _placeholderAvatar(ColorScheme scheme) {
    return Container(
      width: _avatarSize,
      height: _avatarSize,
      // 占位也要是圆形, 未登录时头像是单独出现的, 没有外层裁剪.
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: scheme.surfaceContainerHighest,
      ),
      child: Icon(
        Icons.person,
        size: _avatarSize * 0.6,
        color: scheme.onSurfaceVariant,
      ),
    );
  }
}

/// 昵称后的破会员小标签.
///
/// 只占昵称同一行的高度, 不额外占版面; 非会员不显示这个组件.
class VipBadge extends StatelessWidget {
  const VipBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: Vip.nicknameColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: Vip.nicknameColor.withValues(alpha: 0.35),
          width: 0.8,
        ),
      ),
      child: const Text(
        '破会员',
        style: TextStyle(
          fontSize: 10,
          height: 1.3,
          fontWeight: FontWeight.w600,
          color: Vip.nicknameColor,
        ),
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
