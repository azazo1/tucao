import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tucao/common/widgets/loading_widget.dart';
import 'package:tucao/common/widgets/video_card.dart';
import 'package:tucao/http/space_http.dart';
import 'package:tucao/pages/space/space_controller.dart';
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

  @override
  void dispose() {
    if (Get.isRegistered<SpaceController>(tag: _tag)) {
      Get.delete<SpaceController>(tag: _tag);
    }
    super.dispose();
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
  Widget _buildHeader(BuildContext context, SpaceInfo? info) {
    final scheme = Theme.of(context).colorScheme;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (info != null && info.banner.isNotEmpty)
          CachedNetworkImage(
            imageUrl: info.banner,
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
          ClipOval(
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
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  info.userName,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
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
}
