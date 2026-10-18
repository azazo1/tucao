import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tucao/common/widgets/channel_bar.dart';
import 'package:tucao/common/widgets/loading_widget.dart';
import 'package:tucao/common/widgets/video_card.dart';
import 'package:tucao/http/article_http.dart';
import 'package:tucao/pages/article/article_controller.dart';
import 'package:tucao/router/routes.dart';

/// 档案页.
///
/// 站点 `/data/` 是番组档案与资讯列表, 左侧封面右侧文字,
/// 点按条目进入对应的资讯详情.
class ArticlePage extends StatefulWidget {
  const ArticlePage({super.key, this.embedded = false});

  /// 为 true 时作为首页的标签页使用, 不显示标题栏, 只保留分类选择条.
  final bool embedded;

  @override
  State<ArticlePage> createState() => _ArticlePageState();
}

class _ArticlePageState extends State<ArticlePage> {
  late final String _tag = 'article_${identityHashCode(this)}';

  late final ArticleController _controller = Get.put(
    ArticleController(),
    tag: _tag,
  );

  @override
  void dispose() {
    if (Get.isRegistered<ArticleController>(tag: _tag)) {
      Get.delete<ArticleController>(tag: _tag);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final body = _buildBody();
    if (widget.embedded) {
      return Column(
        children: [
          _buildCategoryBar(),
          Expanded(child: body),
        ],
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('档案'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(42),
          child: _buildCategoryBar(),
        ),
      ),
      body: body,
    );
  }

  Widget _buildCategoryBar() {
    return Obx(
      () => ChannelBar(
        channels: [
          for (var i = 0; i < ArticleController.categoryOptions.length; i++)
            ChannelItem(id: i, name: ArticleController.categoryOptions[i]),
        ],
        currentId: _currentIndex,
        showAll: true,
        allLabel: '全部',
        onChanged: (value) {
          if (value == null) {
            _controller.changeCategory(null);
          } else {
            _controller.changeCategory(
              ArticleController.categoryOptions[value],
            );
          }
        },
      ),
    );
  }

  Widget _buildBody() {
    return Obx(() {
      if (_controller.firstLoading.value) {
        return const LoadingWidget();
      }
      final error = _controller.error.value;
      if (error != null && _controller.list.isEmpty) {
        return ErrorWidgetView(message: error, onRetry: _controller.loadFirst);
      }
      final list = _controller.list;
      return RefreshIndicator(
        onRefresh: _controller.refresh,
        child: NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification.metrics.pixels >=
                notification.metrics.maxScrollExtent - 300) {
              _controller.loadMore();
            }
            return false;
          },
          child: list.isEmpty
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: const [
                    SizedBox(height: 120),
                    EmptyWidget(message: '这个分类下还没有内容'),
                  ],
                )
              : ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  itemCount: list.length + 1,
                  separatorBuilder: (context, index) => const Divider(),
                  itemBuilder: (context, index) {
                    if (index == list.length) {
                      return LoadMoreFooter(
                        loading: _controller.loading.value,
                        hasMore: _controller.hasMore,
                        onRetry: _controller.loadMore,
                      );
                    }
                    return _ArticleItem(item: list[index]);
                  },
                ),
        ),
      );
    });
  }

  int? get _currentIndex {
    final keyword = _controller.keyword.value;
    if (keyword == null) {
      return null;
    }
    final index = ArticleController.categoryOptions.indexOf(keyword);
    return index < 0 ? null : index;
  }
}

/// 一条档案记录.
class _ArticleItem extends StatelessWidget {
  const _ArticleItem({required this.item});

  final ArticleModel item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return InkWell(
      onTap: () => Get.toNamed(
        Routes.article,
        parameters: {'hid': item.hid},
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 110,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: AspectRatio(
                  aspectRatio: 362 / 233,
                  child: item.cover.isEmpty
                      ? ColoredBox(color: scheme.surfaceContainerHighest)
                      : CachedNetworkImage(
                          imageUrl: item.cover,
                          fit: BoxFit.cover,
                          placeholder: (context, url) =>
                              ColoredBox(color: scheme.surfaceContainerHighest),
                          errorWidget: (context, url, error) => ColoredBox(
                            color: scheme.surfaceContainerHighest,
                            child: Icon(
                              Icons.broken_image_outlined,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (item.category.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(bottom: 4),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        item.category,
                        style: TextStyle(
                          fontSize: 11,
                          color: scheme.onSecondaryContainer,
                        ),
                      ),
                    ),
                  Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      height: 1.3,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.summary,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.info,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
