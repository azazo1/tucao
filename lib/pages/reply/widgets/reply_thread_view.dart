import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tucao/models/reply.dart';
import 'package:tucao/pages/reply/reply_thread.dart';
import 'package:tucao/pages/reply/widgets/comment_tile.dart';

/// 收起状态下的楼中楼入口.
///
/// 它作为评论的 footer 放在正文列里, 与所属评论缩进一致.
class ReplyExpandButton extends StatelessWidget {
  const ReplyExpandButton({
    super.key,
    required this.commentId,
    required this.count,
    required this.loading,
    required this.failed,
    required this.onTap,
  });

  final String commentId;
  final int count;
  final bool loading;
  final bool failed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = failed ? scheme.error : scheme.primary;
    final label = loading
        ? '正在加载回复'
        : failed
        ? '回复加载失败, 点击重试'
        : '查看 $count 条回复';
    return Align(
      alignment: Alignment.centerLeft,
      child: InkWell(
        key: ValueKey('reply-toggle-$commentId'),
        onTap: loading ? null : onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (loading)
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.6,
                    color: color,
                  ),
                )
              else
                Icon(
                  failed ? Icons.error_outline : Icons.forum_outlined,
                  size: 14,
                  color: color,
                ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: color),
                ),
              ),
              if (!loading && !failed) ...[
                const SizedBox(width: 2),
                Icon(Icons.expand_more, size: 15, color: color),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 展开后的楼中楼区块.
///
/// 区块有独立的底色和圆角, 头部显示总数与收起入口,
/// 与上方的所属评论在视觉上连成一组.
class ReplyThreadView extends StatelessWidget {
  const ReplyThreadView({
    super.key,
    required this.commentId,
    required this.thread,
    required this.count,
    required this.hasMore,
    required this.supportCountOf,
    required this.isSupported,
    required this.isVipOf,
    required this.onCollapse,
    required this.onLoadMore,
    required this.onRetry,
    required this.onSupport,
    required this.onReply,
  });

  final String commentId;
  final ReplyThread thread;
  final int count;
  final bool hasMore;
  final int Function(ReplyModel reply) supportCountOf;
  final bool Function(ReplyModel reply) isSupported;

  /// 回复者是否是已知的破会员, 楼中楼没有会员信息, 只能靠已知的 uid 判断.
  final bool Function(int uid) isVipOf;

  final VoidCallback onCollapse;
  final VoidCallback onLoadMore;
  final VoidCallback onRetry;
  final void Function(ReplyModel reply) onSupport;
  final void Function(ReplyModel reply) onReply;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final loadingFirst = thread.loading && thread.items.isEmpty;
    return Container(
      key: ValueKey('reply-thread-$commentId'),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.38),
        borderRadius: BorderRadius.circular(10),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(context),
          if (loadingFirst)
            const _StatusRow(text: '正在加载回复')
          else if (thread.items.isEmpty)
            _buildEmpty(context)
          else ...[
            for (var i = 0; i < thread.items.length; i++) ...[
              if (i > 0)
                Divider(
                  height: 1,
                  indent: 10,
                  endIndent: 10,
                  color: scheme.outlineVariant.withValues(alpha: 0.5),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                child: Obx(
                  () => CommentTile(
                    comment: thread.items[i],
                    dense: true,
                    isVip:
                        thread.items[i].isVip ||
                        isVipOf(thread.items[i].userId),
                    supportCount: supportCountOf(thread.items[i]),
                    supported: isSupported(thread.items[i]),
                    onSupport: () => onSupport(thread.items[i]),
                    onReply: () => onReply(thread.items[i]),
                  ),
                ),
              ),
            ],
            if (thread.error != null) _buildError(context),
            if (thread.loadingMore)
              const _StatusRow(text: '正在加载更多回复')
            else if (hasMore && thread.error == null)
              _buildMore(context),
          ],
          const SizedBox(height: 2),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 4, 4, 0),
      child: Row(
        children: [
          Icon(Icons.forum_outlined, size: 14, color: scheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '$count 条回复',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          if (thread.loading && thread.items.isNotEmpty)
            const Padding(
              padding: EdgeInsets.only(right: 6),
              child: SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(strokeWidth: 1.6),
              ),
            ),
          InkWell(
            key: ValueKey('reply-collapse-$commentId'),
            onTap: onCollapse,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '收起',
                    style: TextStyle(fontSize: 12, color: scheme.primary),
                  ),
                  Icon(Icons.expand_less, size: 15, color: scheme.primary),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (thread.error != null) {
      return _buildError(context);
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
      child: Text(
        '暂无可见回复',
        style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
      ),
    );
  }

  Widget _buildError(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 14, color: scheme.error),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '回复加载失败',
              style: TextStyle(fontSize: 12, color: scheme.error),
            ),
          ),
          InkWell(
            key: ValueKey('reply-retry-$commentId'),
            onTap: onRetry,
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              child: Text(
                '重试',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: scheme.primary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMore(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final remaining = count > thread.items.length
        ? count - thread.items.length
        : 0;
    return InkWell(
      key: ValueKey('reply-more-$commentId'),
      onTap: onLoadMore,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '展开更多回复',
              style: TextStyle(fontSize: 12, color: scheme.primary),
            ),
            if (remaining > 0) ...[
              const SizedBox(width: 4),
              Text(
                '(还有 $remaining 条)',
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
              ),
            ],
            Icon(Icons.expand_more, size: 15, color: scheme.primary),
          ],
        ),
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      child: Row(
        children: [
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 1.6,
              color: scheme.primary,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            text,
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
