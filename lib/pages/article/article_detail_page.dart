import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tucao/common/widgets/loading_widget.dart';
import 'package:tucao/http/article_detail_http.dart';
import 'package:tucao/pages/article/widgets/article_stats_bar.dart';
import 'package:tucao/pages/reply/reply_page.dart';
import 'package:tucao/utils/logger.dart';

/// 档案详情控制器.
class ArticleDetailController extends GetxController {
  ArticleDetailController(this.hid);

  final String hid;

  final detail = Rxn<ArticleDetail>();

  final firstLoading = true.obs;

  final error = RxnString();

  @override
  void onInit() {
    super.onInit();
    load();
  }

  Future<void> load() async {
    firstLoading.value = true;
    error.value = null;
    try {
      detail.value = await ArticleDetailHttp.fetch(hid: hid);
    } catch (e, stackTrace) {
      Log.e('加载档案详情失败', error: e, stackTrace: stackTrace);
      error.value = e.toString();
    } finally {
      firstLoading.value = false;
    }
  }
}

/// 档案详情页.
class ArticleDetailPage extends StatefulWidget {
  const ArticleDetailPage({super.key, required this.hid});

  final String hid;

  @override
  State<ArticleDetailPage> createState() => _ArticleDetailPageState();
}

class _ArticleDetailPageState extends State<ArticleDetailPage>
    with SingleTickerProviderStateMixin {
  late final String _tag = 'article_detail_${identityHashCode(this)}';

  late final ArticleDetailController _controller = Get.put(
    ArticleDetailController(widget.hid),
    tag: _tag,
  );

  late final TabController _tabs = TabController(length: 2, vsync: this);

  /// 评论首次选中时才创建, 避免打开正文就拉评论.
  bool _visitedComments = false;

  @override
  void initState() {
    super.initState();
    _tabs.addListener(_onTabChanged);
  }

  void _onTabChanged() {
    if (!_visitedComments && _tabs.index == 1) {
      setState(() => _visitedComments = true);
    }
  }

  @override
  void dispose() {
    _tabs.removeListener(_onTabChanged);
    _tabs.dispose();
    if (Get.isRegistered<ArticleDetailController>(tag: _tag)) {
      Get.delete<ArticleDetailController>(tag: _tag);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('档案'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [Tab(text: '正文'), Tab(text: '评论')],
        ),
      ),
      body: Obx(() {
        if (_controller.firstLoading.value) {
          return const LoadingWidget();
        }
        final error = _controller.error.value;
        if (error != null) {
          return ErrorWidgetView(message: error, onRetry: _controller.load);
        }
        final detail = _controller.detail.value;
        if (detail == null) {
          return const EmptyWidget(message: '没有取到内容');
        }
        return TabBarView(
          controller: _tabs,
          children: [
            _buildArticle(context, detail),
            _buildComments(detail),
          ],
        );
      }),
    );
  }

  Widget _buildArticle(BuildContext context, ArticleDetail detail) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Text(
          detail.title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
            height: 1.4,
          ),
        ),
        if (detail.category.isNotEmpty || detail.publishedAt.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            [
              detail.category,
              detail.publishedAt,
            ].where((e) => e.isNotEmpty).join(' / '),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: 10),
        ArticleStatsBar(hid: detail.hid, commentTypeId: detail.commentTypeId),
        if (detail.tags.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final tag in detail.tags)
                Chip(
                  label: Text(tag),
                  padding: EdgeInsets.zero,
                  labelStyle: const TextStyle(fontSize: 12),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
            ],
          ),
        ],
        const SizedBox(height: 14),
        for (final block in detail.paragraphs) _buildBlock(context, block),
      ],
    );
  }

  Widget _buildComments(ArticleDetail detail) {
    if (detail.commentTypeId <= 0) {
      return const EmptyWidget(message: '该内容没有评论区');
    }
    if (!_visitedComments) {
      return const SizedBox.shrink();
    }
    return ReplyPanel(typeId: detail.commentTypeId, hid: detail.hid);
  }

  Widget _buildBlock(BuildContext context, ArticleBlock block) {
    final scheme = Theme.of(context).colorScheme;
    final image = block.image;
    if (image != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: CachedNetworkImage(
            imageUrl: image,
            fit: BoxFit.contain,
            placeholder: (context, url) => const SizedBox(height: 120),
            errorWidget: (context, url, error) => ColoredBox(
              color: scheme.surfaceContainerHighest,
              child: SizedBox(
                height: 120,
                child: Icon(
                  Icons.broken_image_outlined,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Text(
        block.text ?? '',
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.7),
      ),
    );
  }
}
