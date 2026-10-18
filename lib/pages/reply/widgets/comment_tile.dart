import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:tucao/common/constants.dart';
import 'package:tucao/models/reply.dart';
import 'package:tucao/pages/reply/reply_controller.dart';

/// 单条评论.
///
/// [footer] 放在正文与操作行下方的内容列里, 用来承载楼中楼的入口或展开区.
/// 这样入口天然跟随所属评论缩进, 不会看起来像下一条评论的标题.
class CommentTile extends StatelessWidget {
  const CommentTile({
    super.key,
    required this.comment,
    required this.supportCount,
    required this.supported,
    required this.onSupport,
    required this.onReply,
    this.dense = false,
    this.footer,
  });

  final ReplyModel comment;
  final int supportCount;
  final bool supported;
  final VoidCallback onSupport;
  final VoidCallback onReply;

  /// 楼中楼里的紧凑样式.
  final bool dense;

  /// 正文下方的附加内容.
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final avatarSize = dense ? 26.0 : 36.0;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CommentAvatar(url: comment.avatar, size: avatarSize),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(context),
              const SizedBox(height: 3),
              _buildContent(context),
              const SizedBox(height: 4),
              _buildActions(context),
              if (footer != null) ...[const SizedBox(height: 6), footer!],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final name = comment.userName.isEmpty ? '匿名' : comment.userName;
    return Wrap(
      spacing: 6,
      runSpacing: 2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: dense ? 12 : 13,
            fontWeight: FontWeight.w500,
            color: scheme.onSurface,
          ),
        ),
        if (comment.createAt.isNotEmpty)
          Text(
            comment.createAt,
            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
          ),
      ],
    );
  }

  Widget _buildContent(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = TextStyle(
      fontSize: dense ? 13 : 14,
      height: 1.4,
      color: scheme.onSurface,
    );
    final text = cleanReplyContent(comment.content);
    final mention = dense && comment.replyUserName.isNotEmpty
        ? comment.replyUserName
        : null;
    if (text.isEmpty) {
      return Text(
        '内容不可见',
        style: style.copyWith(
          color: scheme.onSurfaceVariant,
          fontStyle: FontStyle.italic,
        ),
      );
    }
    if (mention == null) {
      return Text(text, style: style);
    }
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '回复 @$mention: ',
            style: TextStyle(color: scheme.primary),
          ),
          TextSpan(text: text),
        ],
      ),
      style: style,
    );
  }

  Widget _buildActions(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 14,
      runSpacing: 2,
      children: [
        _ActionButton(
          icon: supported ? Icons.thumb_up : Icons.thumb_up_outlined,
          label: supportCount > 0 ? '$supportCount' : '赞',
          color: supported ? scheme.primary : scheme.onSurfaceVariant,
          onTap: onSupport,
        ),
        _ActionButton(
          icon: Icons.chat_bubble_outline,
          label: '回复',
          color: scheme.onSurfaceVariant,
          onTap: onReply,
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(fontSize: 12, color: color)),
          ],
        ),
      ),
    );
  }
}

/// 评论头像, 站点偶尔返回相对路径.
class CommentAvatar extends StatelessWidget {
  const CommentAvatar({super.key, required this.url, required this.size});

  final String url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fallback = ColoredBox(
      color: scheme.surfaceContainerHighest,
      child: Icon(
        Icons.person_outline,
        size: size * 0.6,
        color: scheme.onSurfaceVariant,
      ),
    );
    final image = resolveReplyAvatar(url);
    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: image.isEmpty
            ? fallback
            : CachedNetworkImage(
                imageUrl: image,
                fit: BoxFit.cover,
                fadeInDuration: const Duration(milliseconds: 150),
                placeholder: (context, url) =>
                    ColoredBox(color: scheme.surfaceContainerHighest),
                errorWidget: (context, url, error) => fallback,
              ),
      ),
    );
  }
}

/// 头像地址补全, 站点偶尔返回相对路径.
String resolveReplyAvatar(String raw) {
  if (raw.isEmpty) {
    return '';
  }
  if (raw.startsWith('http://') || raw.startsWith('https://')) {
    return raw;
  }
  if (raw.startsWith('//')) {
    return 'https:$raw';
  }
  final path = raw.startsWith('/') ? raw.substring(1) : raw;
  return '${Constants.baseUrl}$path';
}
