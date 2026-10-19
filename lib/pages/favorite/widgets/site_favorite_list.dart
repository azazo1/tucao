import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tucao/common/adaptive.dart';
import 'package:tucao/common/widgets/loading_widget.dart';
import 'package:tucao/common/widgets/video_card.dart';
import 'package:tucao/models/site_favorite.dart';
import 'package:tucao/pages/video/video_page.dart';
import 'package:tucao/services/site_favorite_service.dart';

/// 站点账号的追番列表.
///
/// 内容与官网会员中心的追番夹一致, 取消也走站点的取消地址;
/// 站点没有查询单条状态的接口, 因此整份列表都缓存在服务里.
class SiteFavoriteList extends StatefulWidget {
  const SiteFavoriteList({super.key});

  @override
  State<SiteFavoriteList> createState() => _SiteFavoriteListState();
}

class _SiteFavoriteListState extends State<SiteFavoriteList> {
  late final SiteFavoriteService _service = SiteFavoriteService.instance;
  final _removing = <int>{};
  bool get _current => mounted && ModalRoute.of(context)?.isCurrent == true;

  @override
  void initState() {
    super.initState();
    // 播放页通常已经拉过一次, 这里只是没拉到过时补上.
    unawaited(_service.ensureLoaded());
  }

  Future<void> _remove(SiteFavoriteItem item) async {
    if (_removing.contains(item.recordId) || !_current) {
      return;
    }
    setState(() => _removing.add(item.recordId));
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('取消追番'),
          content: Text('将从站点账号的追番里移除 ${item.title}, 确定继续吗?'),
          actions: [
            TextButton(
              key: const ValueKey('site-favorite-cancel'),
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('保留'),
            ),
            FilledButton(
              key: const ValueKey('site-favorite-confirm'),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('取消追番'),
            ),
          ],
        ),
      );
      if (confirmed == true && _current) {
        await _service.remove(item);
        if (mounted && _current) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('已取消追番')));
        }
      }
    } catch (error) {
      if (mounted && _current) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('取消追番失败: $error')));
      }
    } finally {
      if (mounted) {
        setState(() => _removing.remove(item.recordId));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final side = Adaptive.sidePadding(context, maxWidth: Adaptive.listMaxWidth);
    return Obx(() {
      final error = _service.error.value;
      final items = _service.list;
      return Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text('与站点账号同步, 需要登录'),
          ),
          Expanded(child: _buildBody(items, error, side)),
        ],
      );
    });
  }

  Widget _buildBody(
    List<SiteFavoriteItem> items,
    String? error,
    double side,
  ) {
    if (_service.loading.value && items.isEmpty) {
      return const LoadingWidget();
    }
    if (items.isEmpty) {
      return EmptyWidget(
        message: error ?? '还没有站点追番',
        icon: Icons.star_outline,
        onRetry: error == null
            ? null
            : () => unawaited(_service.refresh(force: true)),
      );
    }
    return RefreshIndicator(
      onRefresh: () => _service.refresh(force: true),
      child: ListView.separated(
        // 条数少时列表不满一屏, 也允许下拉刷新.
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.symmetric(horizontal: side + 12),
        itemCount: items.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final item = items[index];
          return _SiteFavoriteRow(
            key: ValueKey('site-favorite-${item.recordId}'),
            item: item,
            busy: _removing.contains(item.recordId),
            onRemove: () => _remove(item),
          );
        },
      ),
    );
  }
}

/// 追番夹里的一条, 与本地收藏一样给卡片留出取消按钮.
class _SiteFavoriteRow extends StatelessWidget {
  const _SiteFavoriteRow({
    super.key,
    required this.item,
    required this.busy,
    required this.onRemove,
  });

  final SiteFavoriteItem item;
  final bool busy;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final video = item.video;
    final subtitle = [
      if (item.typeName.isNotEmpty) item.typeName,
      if (item.userName.isNotEmpty) item.userName,
      if (item.savedDate.isNotEmpty) item.savedDate,
    ].join(' · ');
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 130, child: VideoCover(url: item.cover)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    height: 1.35,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            key: ValueKey('site-favorite-remove-${item.recordId}'),
            tooltip: '取消追番',
            onPressed: busy ? null : onRemove,
            icon: busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.star),
          ),
        ],
      ),
    );
    return video == null
        ? row
        : InkWell(
            onTap: () => VideoPage.open(video),
            borderRadius: BorderRadius.circular(12),
            child: row,
          );
  }
}
