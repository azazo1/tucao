import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tucao/common/widgets/loading_widget.dart';
import 'package:tucao/common/widgets/video_card.dart';
import 'package:tucao/common/widgets/vip_gold.dart';
import 'package:tucao/http/space_http.dart';
import 'package:tucao/pages/mine/image_viewer_page.dart';
import 'package:tucao/pages/space/space_controller.dart';
import 'package:tucao/router/routes.dart';
import 'package:tucao/services/account_service.dart';
import 'package:tucao/utils/logger.dart';
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
      Get.snackbar('已退出登录', '本地登录信息与 cookie 已清除');
    } catch (e, stackTrace) {
      Log.e('退出登录失败', error: e, stackTrace: stackTrace);
      if (mounted) {
        Get.snackbar('退出登录失败', '$e');
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
            appBar: AppBar(title: const Text('用户')),
            body: const LoadingWidget(),
          );
        }
        final error = _controller.error.value;
        if (error != null && _controller.list.isEmpty) {
          return Scaffold(
            appBar: AppBar(title: const Text('用户')),
            body: ErrorWidgetView(
              message: error,
              onRetry: _controller.loadFirst,
            ),
          );
        }
        final info = _controller.info.value;
        return RefreshIndicator(
          onRefresh: _controller.refresh,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverAppBar(
                pinned: true,
                expandedHeight: 180,
                flexibleSpace: FlexibleSpaceBar(
                  background: _buildHeader(context, info),
                ),
              ),
              SliverToBoxAdapter(child: _buildStats(context, info)),
              SliverToBoxAdapter(child: _buildAccountActions(context)),
              if (_controller.list.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyWidget(message: '这位 up 还没有投稿'),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  sliver: SliverList.separated(
                    itemCount: _controller.list.length,
                    separatorBuilder: (context, index) => const Divider(),
                    itemBuilder: (context, index) => VideoCardHorizontal(
                      video: _controller.list[index],
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

  /// 顶部背景图与头像.
  ///
  /// 背景图与头像是站点给的原图, 点一下可以放大查看, 长按保存.
  Widget _buildHeader(BuildContext context, SpaceInfo? info) {
    final scheme = Theme.of(context).colorScheme;
    final banner = info?.banner ?? '';
    final background = Stack(
      fit: StackFit.expand,
      children: [
        if (banner.isNotEmpty)
          CachedNetworkImage(
            imageUrl: banner,
            fit: BoxFit.cover,
            placeholder: (context, url) =>
                ColoredBox(color: scheme.surfaceContainerHighest),
            errorWidget: (context, url, error) =>
                ColoredBox(color: scheme.surfaceContainerHighest),
          )
        else
          ColoredBox(color: scheme.surfaceContainerHighest),
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

  /// 自己的主页上显示账号操作, 别人的主页不显示.
  Widget _buildAccountActions(BuildContext context) {
    return Obx(() {
      if (!_isOwnProfile) {
        return const SizedBox.shrink();
      }
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
    });
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
                        placeholder: (context, url) => ColoredBox(
                          color: scheme.surfaceContainerHighest,
                        ),
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
                _buildName(theme, info),
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
  Widget _buildName(ThemeData theme, SpaceInfo info) {
    final name = Text(
      info.userName,
      style: theme.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w600,
      ),
    );
    if (!info.isVip) {
      return name;
    }
    return VipGold(particleSeed: info.userId, child: name);
  }
}
