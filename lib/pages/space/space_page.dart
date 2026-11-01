import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tucao/utils/toast.dart';
import 'package:tucao/common/widgets/loading_widget.dart';
import 'package:tucao/common/widgets/page_more_menu.dart';
import 'package:tucao/common/widgets/user_banner.dart';
import 'package:tucao/common/widgets/video_card.dart';
import 'package:tucao/common/widgets/vip_gold.dart';
import 'package:tucao/http/space_http.dart';
import 'package:tucao/pages/mine/image_viewer_page.dart';
import 'package:tucao/pages/space/private_message_sheet.dart';
import 'package:tucao/pages/space/space_controller.dart';
import 'package:tucao/router/routes.dart';
import 'package:tucao/services/account_service.dart';
import 'package:tucao/services/block_service.dart';
import 'package:tucao/utils/clipboard.dart';
import 'package:tucao/utils/logger.dart';
import 'package:tucao/utils/site_links.dart';
import 'package:tucao/utils/utils.dart';

/// 用户空间页, 即投稿人主页.
///
/// 站点地址是 `play/u{uid}/`, 头部是背景图与头像, 下面是投稿列表.
class SpacePage extends StatefulWidget {
  const SpacePage({super.key, required this.userId});

  final int userId;

  @override
  State<SpacePage> createState() => _SpacePageState();
}

class _SpacePageState extends State<SpacePage> {
  late final String _tag = 'space_${identityHashCode(this)}';

  late final SpaceController _controller = Get.put(
    SpaceController(widget.userId),
    tag: _tag,
  );

  bool _loggingOut = false;

  /// 只有查看自己的空间时才显示账号操作.
  bool get _isOwnProfile {
    final user = AccountService.instance.user.value;
    return user != null && user.userId > 0 && user.userId == widget.userId;
  }

  /// 是否是游客弹幕的聚合账号.
  ///
  /// 站点把未登录用户发的弹幕统计在 uid 0 名下, u 榜里名为 网友.
  /// 这类账号没有资料与投稿, 打开空间页会是一片空白, 需要单独说明.
  bool get _isGuestAggregate => widget.userId == 0;

  @override
  void dispose() {
    if (Get.isRegistered<SpaceController>(tag: _tag)) {
      Get.delete<SpaceController>(tag: _tag);
    }
    super.dispose();
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
      if (!mounted) {
        return;
      }
      Get.back();
      Toast.show('已退出登录', detail: '本地登录信息与 cookie 已清除');
    } catch (e, stackTrace) {
      Log.e('退出登录失败', error: e, stackTrace: stackTrace);
      if (mounted) {
        Toast.show('退出登录失败', detail: '$e');
      }
    } finally {
      if (mounted) {
        setState(() => _loggingOut = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Obx(() {
        if (_controller.firstLoading.value) {
          return Scaffold(
            appBar: AppBar(title: const Text('用户'), actions: [_moreMenu()]),
            body: const LoadingWidget(),
          );
        }
        final error = _controller.error.value;
        if (error != null && _controller.list.isEmpty) {
          return Scaffold(
            appBar: AppBar(title: const Text('用户'), actions: [_moreMenu()]),
            body: ErrorWidgetView(
              message: error,
              onRetry: _controller.loadFirst,
            ),
          );
        }
        final info = _controller.info.value;
        // 站点对不存在或已注销的 uid 也返回 200, 页面只剩默认背景与空投稿,
        // 不提示的话看起来像加载失败.
        if (info != null && !info.exists) {
          return Scaffold(
            appBar: AppBar(title: const Text('用户'), actions: [_moreMenu()]),
            body: const EmptyWidget(
              message: '用户不存在, 可能链接有误或账号已注销',
              icon: Icons.person_off_outlined,
            ),
          );
        }
        final raw = _controller.list;
        final items = raw.withoutBlocked();
        return RefreshIndicator(
          onRefresh: _controller.refresh,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverAppBar(
                pinned: true,
                expandedHeight: 180,
                actions: [_moreMenu()],
                flexibleSpace: FlexibleSpaceBar(
                  background: _buildHeader(context, info),
                ),
              ),
              SliverToBoxAdapter(child: _buildStats(context, info)),
              if (_isGuestAggregate)
                SliverToBoxAdapter(child: _buildGuestNotice(context)),
              SliverToBoxAdapter(child: _buildActions(context)),
              if (items.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyWidget(
                    message: raw.isEmpty
                        ? (_isGuestAggregate
                              ? '游客弹幕没有对应的投稿'
                              : '这位 up 还没有投稿')
                        : '投稿都已被屏蔽',
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  sliver: SliverList.separated(
                    itemCount: items.length,
                    separatorBuilder: (context, index) => const Divider(),
                    itemBuilder: (context, index) => VideoCardHorizontal(
                      video: items[index],
                      showDescription: false,
                    ),
                  ),
                ),
              SliverToBoxAdapter(
                child: LoadMoreFooter(
                  loading: _controller.loading.value,
                  hasMore: _controller.hasMore,
                  onRetry: _controller.loadMore,
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  Widget _moreMenu() => PageMoreMenu(uri: SiteLinks.space(widget.userId));

  /// 顶部背景图与头像.
  ///
  /// 背景图与头像是站点给的原图, 点一下可以放大查看, 长按保存.
  Widget _buildHeader(BuildContext context, SpaceInfo? info) {
    final banner = info?.banner ?? '';
    final background = Stack(
      fit: StackFit.expand,
      children: [
        UserBanner(url: banner),
        // 压暗背景, 保证上方标题可读.
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.45),
                Colors.black.withValues(alpha: 0.15),
              ],
            ),
          ),
        ),
      ],
    );
    if (banner.isEmpty) {
      return background;
    }
    return GestureDetector(
      onTap: () => _openImage(
        url: banner,
        title: '${info?.userName ?? ''} 的横幅'.trim(),
        prefix: 'banner',
      ),
      child: background,
    );
  }

  /// 放大查看某张图片, 是否保存由查看页里的长按与按钮决定.
  void _openImage({
    required String url,
    required String title,
    required String prefix,
  }) {
    if (url.isEmpty) {
      return;
    }
    Get.to(() => ImageViewerPage(url: url, title: title, prefix: prefix));
  }

  /// 自己的空间显示账号操作, 别人的空间显示私信入口.
  Widget _buildActions(BuildContext context) {
    return Obx(() {
      if (_isOwnProfile) {
        return _buildAccountActions(context);
      }
      // 游客聚合账号没有接收私信的用户名, 不显示入口.
      if (_isGuestAggregate) {
        return const SizedBox.shrink();
      }
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
        child: Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: () => _openPrivateMessage(context),
            icon: const Icon(Icons.mail_outline, size: 18),
            label: const Text('私信'),
          ),
        ),
      );
    });
  }

  /// 给空间主人发私信.
  ///
  /// 站点发送私信需要登录态, 未登录时先提示, 不去请求一个必然失败的接口.
  /// 收件人要传空间页私信链接里的用户名, 不是 uid.
  /// 发送成功后只能提示去私信页查看: 站点只回一个成功标记, 拿不到新会话的
  /// messageid, 无法直接跳进会话页.
  Future<void> _openPrivateMessage(BuildContext context) async {
    if (!AccountService.instance.isLogin) {
      Toast.show('请先登录', detail: '登录后才能给其他用户发私信');
      return;
    }
    final info = _controller.info.value;
    final loginName = info?.loginName.trim() ?? '';
    if (loginName.isEmpty) {
      Toast.show('找不到对方账号', detail: '空间页里没有私信入口');
      return;
    }
    final sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => PrivateMessageSheet(
        toUserName: loginName,
        displayName: info?.userName ?? '',
      ),
    );
    if (sent == true && mounted) {
      Toast.show('私信已发送', detail: '可以在「我的 - 私信」里查看');
    }
  }

  /// 自己的主页上显示账号操作.
  Widget _buildAccountActions(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          OutlinedButton.icon(
            onPressed: () => Get.toNamed(Routes.changePassword),
            icon: const Icon(Icons.password_outlined, size: 18),
            label: const Text('修改密码'),
          ),
          TextButton.icon(
            onPressed: _loggingOut ? null : _logout,
            style: TextButton.styleFrom(foregroundColor: scheme.error),
            icon: _loggingOut
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.logout, size: 18),
            label: const Text('退出登录'),
          ),
        ],
      ),
    );
  }

  /// 游客弹幕聚合账号的说明.
  ///
  /// 这类账号的资料与投稿都是空的, 需要在页面上说明来源, 免得看起来像加载失败.
  Widget _buildGuestNotice(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 18, color: scheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('游客弹幕聚合账号', style: theme.textTheme.labelLarge),
                const SizedBox(height: 4),
                Text(
                  '未登录用户发的弹幕都统计在这个账号下, 它在 u 榜里显示为 '
                  '${SpaceHttp.guestUserName}. 站点没有为它建立资料, 因此这里没有'
                  '头像, 昵称和投稿.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStats(BuildContext context, SpaceInfo? info) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    if (info == null) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => _openImage(
              url: info.avatar,
              title: '${info.userName} 的头像',
              prefix: 'avatar',
            ),
            child: ClipOval(
              child: SizedBox(
                width: 56,
                height: 56,
                child: info.avatar.isEmpty
                    ? ColoredBox(
                        color: scheme.surfaceContainerHighest,
                        child: Icon(
                          Icons.person,
                          color: scheme.onSurfaceVariant,
                        ),
                      )
                    : CachedNetworkImage(
                        imageUrl: info.avatar,
                        fit: BoxFit.cover,
                        placeholder: (context, url) =>
                            ColoredBox(color: scheme.surfaceContainerHighest),
                        errorWidget: (context, url, error) => ColoredBox(
                          color: scheme.surfaceContainerHighest,
                          child: Icon(
                            Icons.person,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildName(context, theme, info),
                if (info.userId > 0) ...[
                  const SizedBox(height: 4),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onLongPress: () =>
                        copyText(context, info.userId.toString()),
                    child: Text(
                      '用户 id: ${info.userId}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
                if (info.meta.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    info.meta,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
                if (info.sign.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    info.sign,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
                  ),
                ],
                const SizedBox(height: 6),
                Text(
                  '投稿 ${Utils.formatCount(info.total)}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 空间主人的昵称.
  ///
  /// 破会员套一层金色流光, 与我的页面保持一致; 普通用户仍用主题色.
  /// 长按昵称直接复制名称.
  Widget _buildName(BuildContext context, ThemeData theme, SpaceInfo info) {
    final name = Text(
      info.userName,
      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    );
    final child = info.isVip
        ? VipGold(particleSeed: info.userId, child: name)
        : name;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: () => copyText(context, info.userName),
      child: child,
    );
  }
}
