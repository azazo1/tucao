import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tucao/common/widgets/paging_list.dart';
import 'package:tucao/http/message_http.dart';
import 'package:tucao/models/message.dart';
import 'package:tucao/router/routes.dart';
import 'package:tucao/services/account_service.dart';
import 'package:tucao/utils/logger.dart';

/// 评论列表控制器.
///
/// 站点按页返回评论, 是否还有下一页由页面里的分页链接决定, 不按本页条数猜.
class CommentListController extends GetxController {
  final list = <CommentMessage>[].obs;

  final firstLoading = true.obs;

  final error = RxnString();

  final loadingMore = false.obs;

  final hasMore = false.obs;

  int _page = 1;

  bool get isLogin => AccountService.instance.isLogin;

  @override
  void onInit() {
    super.onInit();
    load();
  }

  Future<void> load() async {
    firstLoading.value = true;
    error.value = null;
    try {
      if (!isLogin) {
        error.value = '请先登录后查看评论';
        return;
      }
      final result = await MessageHttp.comments();
      list.assignAll(result.list);
      hasMore.value = result.hasMore;
      _page = 1;
    } catch (e, stackTrace) {
      Log.e('加载评论列表失败', error: e, stackTrace: stackTrace);
      error.value = e.toString();
    } finally {
      firstLoading.value = false;
    }
  }

  @override
  Future<void> refresh() => load();

  Future<void> loadMore() async {
    if (loadingMore.value || !hasMore.value) {
      return;
    }
    loadingMore.value = true;
    try {
      final next = _page + 1;
      final result = await MessageHttp.comments(page: next);
      list.addAll(result.list);
      hasMore.value = result.hasMore;
      _page = next;
    } catch (e, stackTrace) {
      Log.e('加载更多评论失败', error: e, stackTrace: stackTrace);
    } finally {
      loadingMore.value = false;
    }
  }
}

/// 评论列表, 供评论页使用.
class CommentListView extends StatefulWidget {
  const CommentListView({super.key});

  @override
  State<CommentListView> createState() => _CommentListViewState();
}

class _CommentListViewState extends State<CommentListView> {
  late final String _tag = 'message_comment_${identityHashCode(this)}';

  late final CommentListController _controller = Get.put(
    CommentListController(),
    tag: _tag,
  );

  @override
  void dispose() {
    if (Get.isRegistered<CommentListController>(tag: _tag)) {
      Get.delete<CommentListController>(tag: _tag);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Obx(
      () => PagingList<CommentMessage>(
        list: _controller.list,
        firstLoading: _controller.firstLoading.value,
        error: _controller.error.value,
        onRetry: _controller.load,
        onRefresh: _controller.refresh,
        onLoadMore: _controller.loadMore,
        hasMore: _controller.hasMore.value,
        loading: _controller.loadingMore.value,
        emptyMessage: '还没有发表过评论',
        padding: const EdgeInsets.symmetric(vertical: 4),
        separator: const Divider(height: 1),
        itemBuilder: (context, item, index) => _CommentTile(item: item),
      ),
    );
  }
}

/// 一条评论, 左边是内容封面, 右边是分区, 标题, 作者与评论正文.
class _CommentTile extends StatelessWidget {
  const _CommentTile({required this.item});

  final CommentMessage item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final target = item.target;
    return InkWell(
      onTap: target == null ? null : () => _open(target),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Cover(url: item.cover),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (item.category.isNotEmpty)
                    Text(
                      item.category,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  const SizedBox(height: 2),
                  Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (item.author.isNotEmpty || item.time.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    _Meta(item: item),
                  ],
                  if (item.content.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      item.content,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 打开被评论的内容, 档案与视频走不同的页面.
  void _open(CommentTarget target) {
    if (target.article) {
      Get.toNamed(Routes.article, parameters: {'hid': target.hid});
      return;
    }
    Get.toNamed(Routes.video, parameters: {'hid': target.hid});
  }
}

/// 作者与评论时间, 作者可点进空间.
class _Meta extends StatelessWidget {
  const _Meta({required this.item});

  final CommentMessage item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final style = theme.textTheme.labelSmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    final authorId = item.authorId;
    return Row(
      children: [
        if (item.author.isNotEmpty)
          Flexible(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: authorId.isEmpty
                  ? null
                  : () => Get.toNamed(
                      Routes.space,
                      parameters: {'uid': authorId},
                    ),
              child: Text(
                item.author,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: authorId.isEmpty
                    ? style
                    : style?.copyWith(color: scheme.primary),
              ),
            ),
          ),
        if (item.author.isNotEmpty && item.time.isNotEmpty)
          Text(' · ', style: style),
        if (item.time.isNotEmpty) Text(item.time, style: style),
      ],
    );
  }
}

/// 被评论内容的封面, 与站点列表里的缩略图一致.
class _Cover extends StatelessWidget {
  const _Cover({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: 112,
        height: 70,
        child: url.isEmpty
            ? ColoredBox(
                color: scheme.surfaceContainerHighest,
                child: Icon(
                  Icons.movie_outlined,
                  size: 20,
                  color: scheme.onSurfaceVariant,
                ),
              )
            : CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                placeholder: (context, url) =>
                    ColoredBox(color: scheme.surfaceContainerHighest),
                errorWidget: (context, url, error) => ColoredBox(
                  color: scheme.surfaceContainerHighest,
                  child: Icon(
                    Icons.movie_outlined,
                    size: 20,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
      ),
    );
  }
}
