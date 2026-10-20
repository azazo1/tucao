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
import 'package:tucao/common/widgets/vip_gold.dart';
import 'package:tucao/http/space_http.dart';
import 'package:tucao/models/user.dart';
import 'package:tucao/pages/life/widgets/life_card.dart';
import 'package:tucao/common/widgets/user_banner.dart';
import 'package:tucao/pages/mine/widgets/update_download_panel.dart';
import 'package:tucao/router/routes.dart';
import 'package:tucao/services/account_service.dart';
import 'package:tucao/services/message_count_service.dart';
import 'package:tucao/services/update/update_download_service.dart';
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

  /// 手动刷新登录状态的次数, 头像横幅与续命卡片据此重新取数.
  int _refreshTick = 0;

  /// 刷新请求进行中, 避免下拉手势连续触发重复请求.
  bool _refreshing = false;

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
      // 检查更新与下载都在对话框内部处理: 提示框叠在它上面, 关掉提示后
      // 仍然停在关于页, 下载进度与安装入口就在眼前.
      builder: (_) => _AboutDialog(version: _version),
    );
  }

  /// 刷新当前登录状态.
  ///
  /// 头像横幅与续命卡片不会跟着账号信息自动更新, 这里一并重新取数,
  /// 顺带把私信与评论的未读数也更新一次.
  Future<void> _refresh() async {
    if (_refreshing) {
      return;
    }
    _refreshing = true;
    try {
      await Future.wait([
        AccountService.instance.refresh(),
        MessageCountService.instance.reload(),
      ]);
      if (!mounted) {
        return;
      }
      setState(() => _refreshTick++);
    } finally {
      _refreshing = false;
    }
  }

  /// 打开反馈页.
  ///
  /// 反馈以站点私信发给开发者, 成功后回到本页再提示一次, 避免提示条
  /// 跟着被关掉的页面一起消失.
  Future<void> _openFeedback() async {
    final sent = await Get.toNamed<bool>(Routes.feedback);
    if (sent == true && mounted) {
      Get.snackbar('反馈已发送', '已通过私信发给开发者, 可在「我的 - 私信」里查看');
    }
  }

  /// 打开消息类入口.
  ///
  /// 站点的已读状态在打开会话时才清掉, 回到本页要重新取一次未读数,
  /// 否则刚看完的私信还挂在入口上.
  Future<void> _openMessage(String route) async {
    await Get.toNamed(route);
    await MessageCountService.instance.reload();
  }

  /// 续命卡片.
  ///
  /// 数据来自会员中心, 需要登录态, 未登录时这一块不占位置;
  /// 登录态变化或手动刷新时换 key, 卡片会跟着重新取数.
  Widget _lifeSection() {
    return Obx(() {
      final user = AccountService.instance.user.value;
      if (user == null) {
        return const SizedBox.shrink();
      }
      return Padding(
        padding: Style.pagePadding.add(const EdgeInsets.only(top: 12)),
        child: LifeCard(key: ValueKey('life-${user.userId}-$_refreshTick')),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.symmetric(
            horizontal: Adaptive.sidePadding(context),
            vertical: 12,
          ),
          children: [
            Padding(
              padding: Style.pagePadding,
              child: _UserHeader(refreshTick: _refreshTick),
            ),
            _lifeSection(),
            const SizedBox(height: 16),
            _MessageEntry(
              icon: Icons.mail_outline,
              label: '私信',
              count: MessageCountService.instance.inbox,
              onTap: () => _openMessage(Routes.inbox),
            ),
            _MessageEntry(
              icon: Icons.comment_outlined,
              label: '评论',
              count: MessageCountService.instance.comment,
              onTap: () => _openMessage(Routes.comment),
            ),
            ListTile(
              leading: const Icon(Icons.history),
              title: const Text('播放历史'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Get.toNamed(Routes.history),
            ),
            ListTile(
              leading: const Icon(Icons.star_outline),
              title: const Text('我的收藏'),
              subtitle: const Text('本地收藏与站点追番'),
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
              leading: const Icon(Icons.feedback_outlined),
              title: const Text('向开发者反馈'),
              subtitle: const Text('以站点私信发给开发者, 需要登录'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _openFeedback,
            ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('关于'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _showAbout,
            ),
          ],
        ),
      ),
    );
  }
}

/// 消息类入口.
///
/// 有未读时图标上带一个红点, 标题后面跟上未读数量; 数量只写在标题里,
/// 图标上的圆点不再重复数字. 未读数由服务持有, 组件自己订阅它, 数字变化时
/// 只重建这一项.
class _MessageEntry extends StatelessWidget {
  const _MessageEntry({
    required this.icon,
    required this.label,
    required this.count,
    required this.onTap,
  });

  final IconData icon;

  final String label;

  /// 未读数来源.
  final RxInt count;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final unread = count.value;
      return ListTile(
        leading: Badge(isLabelVisible: unread > 0, child: Icon(icon)),
        title: Text(unread > 0 ? '$label ($unread)' : label),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      );
    });
  }
}

/// 顶部账号卡片, 登录状态变化时自动刷新.
///
/// 头像与横幅取自自己的用户空间页: 那个页面应用本来就会访问, 不受站点网页版
/// 会员中心的影响. 有横幅就把它铺在卡片顶部, 没有就退回主题色渐变.
/// 点卡片进自己的用户空间, 点头像或横幅则是放大查看, 放大后长按可保存.
class _UserHeader extends StatefulWidget {
  const _UserHeader({required this.refreshTick});

  /// 手动刷新登录状态的次数, 变化时重新拉取自己的空间资料.
  final int refreshTick;

  @override
  State<_UserHeader> createState() => _UserHeaderState();
}

class _UserHeaderState extends State<_UserHeader> {
  /// 横幅与头像都比默认小一圈, 让这张卡片不至于占掉半个屏幕,
  /// 列表底部的条目也不会被弹出的提示条压住.
  static const _bannerHeight = 80.0;
  static const _avatarSize = 48.0;

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

  @override
  void didUpdateWidget(covariant _UserHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.refreshTick == oldWidget.refreshTick) {
      return;
    }
    // 手动刷新时 uid 通常没变, 上面的监听不会触发, 这里强制重取头像与横幅.
    final current = AccountService.instance.user.value;
    _loadedUserId = 0;
    if (current == null) {
      _info = null;
      return;
    }
    unawaited(_loadSpace(current.userId));
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
                    child: UserBanner(url: banner),
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
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(child: _buildName(user)),
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

  /// 昵称.
  ///
  /// 破会员套一层金色流光, 与点进来的空间页保持一致; 普通用户的昵称仍用
  /// 主题色.
  Widget _buildName(UserModel user) {
    final name = Text(
      user.displayName,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
    );
    if (!user.isVip) {
      return name;
    }
    return VipGold(particleSeed: user.userId, child: name);
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
/// 底色, 描边与文字都由外层的金色流光上色, 三层只是透明度不同.
class VipBadge extends StatelessWidget {
  const VipBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return VipGold(
      particleCount: 5,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
          color: Vip.gold.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: Vip.goldDeep.withValues(alpha: 0.5),
            width: 0.8,
          ),
        ),
        child: const Text(
          '破会员',
          style: TextStyle(
            fontSize: 10,
            height: 1.3,
            fontWeight: FontWeight.w600,
            color: Vip.gold,
          ),
        ),
      ),
    );
  }
}

/// 关于对话框.
///
/// 检查更新与下载状态都在这里: 更新提示对话框叠在它上面, 关掉提示后仍然
/// 停在关于页, 下载进度与安装入口就近可见.
class _AboutDialog extends StatefulWidget {
  const _AboutDialog({required this.version});

  final String version;

  @override
  State<_AboutDialog> createState() => _AboutDialogState();
}

class _AboutDialogState extends State<_AboutDialog> {
  /// 正在向 GitHub 查询, 期间禁用两个入口, 避免重复请求.
  bool _checking = false;

  /// 上一次检查的结果; 发现新版本时由更新提示对话框代替它.
  String _message = '';

  Future<void> _check({required bool dev}) async {
    if (_checking) {
      return;
    }
    setState(() {
      _checking = true;
      _message = '';
    });
    try {
      final message = dev
          ? await UpdateService.checkDevManually(context)
          : await UpdateService.checkManually(context);
      if (!mounted) {
        return;
      }
      setState(() => _message = message ?? '');
    } finally {
      if (mounted) {
        setState(() => _checking = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final download = UpdateDownloadService.maybeInstance;
    return AlertDialog(
      // 关闭改到右上角, 底部只留两个检查入口, 360dp 下也能排成一行.
      title: Row(
        children: [
          Expanded(child: Text(Constants.appName)),
          IconButton(
            onPressed: () => Get.back(),
            tooltip: '关闭',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close),
          ),
        ],
      ),
      // 下载状态会临时撑高这一列, 小屏上让它自己滚.
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.version.isEmpty ? '版本读取中' : '版本 ${widget.version}',
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
            // 检查结果直接显示在框内, 提示条会被本对话框挡住.
            if (_checking || _message.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  _checking ? '正在检查更新...' : _message,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            // 更新包的下载在对话框之外继续, 这里接着显示进度与安装入口.
            if (download != null) UpdateDownloadPanel(service: download),
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
      ),
      actions: [
        TextButton(
          onPressed: _checking ? null : () => _check(dev: true),
          child: const Text('检查开发版更新'),
        ),
        TextButton(
          onPressed: _checking ? null : () => _check(dev: false),
          child: const Text('检查更新'),
        ),
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
