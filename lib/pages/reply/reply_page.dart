import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tucao/common/constants.dart';
import 'package:tucao/common/widgets/paging_list.dart';
import 'package:tucao/models/reply.dart';
import 'package:tucao/pages/reply/reply_controller.dart';
import 'package:tucao/services/account_service.dart';
import 'package:tucao/utils/utils.dart';

/// 评论页.
///
/// [part] 是分 P 序号, 从 0 开始.
class ReplyPage extends StatefulWidget {
  const ReplyPage({
    super.key,
    required this.typeId,
    required this.hid,
    this.part = 0,
  });

  /// 视频所在分区, 与 hid 一起构成评论楼层 id.
  final int typeId;

  final String hid;

  /// 当前分P, 仅用于展示; 同一视频的所有分P共用一个评论楼层.
  final int part;

  @override
  State<ReplyPage> createState() => _ReplyPageState();
}

class _ReplyPageState extends State<ReplyPage> {
  late final ReplyController controller;

  @override
  void initState() {
    super.initState();
    // 同一个视频可能被多次打开评论页, 换了视频就换掉旧的注册.
    final existing = Get.isRegistered<ReplyController>()
        ? Get.find<ReplyController>()
        : null;
    if (existing != null && existing.hid != widget.hid) {
      Get.delete<ReplyController>();
    }
    controller = Get.put(
      ReplyController(
        typeId: widget.typeId,
        hid: widget.hid,
        part: widget.part,
      ),
    );
  }

  @override
  void dispose() {
    if (Get.isRegistered<ReplyController>() &&
        identical(Get.find<ReplyController>(), controller)) {
      Get.delete<ReplyController>();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Obx(() {
          final total = controller.total.value;
          return Row(
            children: [
              const Text('评论'),
              if (total > 0) ...[
                const SizedBox(width: 6),
                Text(
                  Utils.formatCount(total),
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          );
        }),
      ),
      body: Column(
        children: [
          Expanded(
            child: Obx(
              () => PagingList<ReplyModel>(
                list: controller.list,
                itemBuilder: _buildItem,
                onRefresh: controller.refresh,
                onLoadMore: controller.loadMore,
                hasMore: controller.hasMore,
                loading: controller.loading.value,
                firstLoading: controller.firstLoading.value,
                error: _cleanError(controller.error.value),
                onRetry: controller.loadFirst,
                emptyMessage: '还没有评论, 来说点什么吧',
                separator: const Divider(),
              ),
            ),
          ),
          _buildInputBar(context),
        ],
      ),
    );
  }

  Widget _buildItem(BuildContext context, ReplyModel comment, int index) {
    return Obx(() {
      final expanded = controller.expanded.contains(comment.id);
      final loading = controller.loadingReplies.contains(comment.id);
      final count = comment.replyCount > comment.replies.length
          ? comment.replyCount
          : comment.replies.length;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CommentTile(
            comment: comment,
            supportCount: controller.supportCount(comment),
            supported: controller.isSupported(comment.id),
            onSupport: () => _support(comment),
            onReply: () => _openInput(replyTo: comment),
          ),
          if (count > 0 || expanded) ...[
            const SizedBox(height: 4),
            _ExpandBar(
              count: count,
              expanded: expanded,
              loading: loading,
              onTap: () => _toggle(comment),
            ),
          ],
          if (expanded)
            for (final reply in comment.replies)
              Padding(
                padding: const EdgeInsets.only(left: 44, top: 8),
                child: _CommentTile(
                  comment: reply,
                  dense: true,
                  supportCount: controller.supportCount(reply),
                  supported: controller.isSupported(reply.id),
                  onSupport: () => _support(reply),
                  onReply: () => _openInput(replyTo: reply),
                ),
              ),
        ],
      );
    });
  }

  Widget _buildInputBar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surface,
          border: Border(
            top: BorderSide(
              color: scheme.outlineVariant.withValues(alpha: 0.5),
              width: 0.5,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Obx(() {
            final sending = controller.sending.value;
            return InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: sending ? null : () => _openInput(),
              child: Container(
                height: 38,
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    if (sending)
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: scheme.onSurfaceVariant,
                        ),
                      )
                    else
                      Icon(
                        Icons.edit_outlined,
                        size: 16,
                        color: scheme.onSurfaceVariant,
                      ),
                    const SizedBox(width: 8),
                    Text(
                      sending ? '正在发送' : '说点什么',
                      style: TextStyle(
                        fontSize: 13,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  /// 展开或收起楼中楼.
  Future<void> _toggle(ReplyModel comment) async {
    try {
      await controller.toggleReplies(comment);
    } catch (e) {
      _toast(_cleanError(e.toString()) ?? '加载回复失败');
    }
  }

  Future<void> _support(ReplyModel comment) async {
    try {
      await controller.support(comment);
    } catch (e) {
      _toast(_cleanError(e.toString()) ?? '点赞失败');
    }
  }

  /// 弹出输入框, 发送评论或回复.
  Future<void> _openInput({ReplyModel? replyTo}) async {
    if (!AccountService.instance.isLogin) {
      _toast('请先登录');
      return;
    }
    final text = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _InputSheet(
        hint: replyTo == null ? '说点什么' : '回复 @${replyTo.userName}',
      ),
    );
    if (text == null || text.trim().isEmpty) {
      return;
    }
    try {
      await controller.send(text, replyTo: replyTo);
      _toast(replyTo == null ? '评论成功' : '回复成功');
    } catch (e) {
      _toast(_cleanError(e.toString()) ?? '发送失败');
    }
  }

  void _toast(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
      );
  }
}

/// 单条评论.
class _CommentTile extends StatelessWidget {
  const _CommentTile({
    required this.comment,
    required this.supportCount,
    required this.supported,
    required this.onSupport,
    required this.onReply,
    this.dense = false,
  });

  final ReplyModel comment;
  final int supportCount;
  final bool supported;
  final VoidCallback onSupport;
  final VoidCallback onReply;

  /// 楼中楼里的紧凑样式.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final size = dense ? 26.0 : 36.0;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Avatar(url: comment.avatar, size: size),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      comment.userName.isEmpty ? '匿名' : comment.userName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: dense ? 12 : 13,
                        fontWeight: FontWeight.w500,
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    comment.createAt,
                    style: TextStyle(
                      fontSize: 11,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                _content(comment),
                style: TextStyle(
                  fontSize: dense ? 13 : 14,
                  height: 1.35,
                  color: scheme.onSurface,
                ),
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  _ActionButton(
                    icon: supported ? Icons.thumb_up : Icons.thumb_up_outlined,
                    label: supportCount > 0 ? '$supportCount' : '赞',
                    color: supported ? scheme.primary : scheme.onSurfaceVariant,
                    onTap: onSupport,
                  ),
                  const SizedBox(width: 16),
                  _ActionButton(
                    icon: Icons.chat_bubble_outline,
                    label: '回复',
                    color: scheme.onSurfaceVariant,
                    onTap: onReply,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 回复他人时在正文前带上被回复人.
  String _content(ReplyModel comment) {
    final text = cleanReplyContent(comment.content);
    if (dense && comment.replyUserName.isNotEmpty) {
      return '回复 @${comment.replyUserName}: $text';
    }
    return text;
  }
}

/// 楼中楼的展开条.
class _ExpandBar extends StatelessWidget {
  const _ExpandBar({
    required this.count,
    required this.expanded,
    required this.loading,
    required this.onTap,
  });

  final int count;
  final bool expanded;
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: loading ? null : onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (loading)
              SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: scheme.primary,
                ),
              )
            else
              Icon(
                expanded ? Icons.expand_less : Icons.expand_more,
                size: 15,
                color: scheme.primary,
              ),
            const SizedBox(width: 4),
            Text(
              expanded ? '收起回复' : '共 $count 条回复',
              style: TextStyle(fontSize: 12, color: scheme.primary),
            ),
          ],
        ),
      ),
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
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
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

class _Avatar extends StatelessWidget {
  const _Avatar({required this.url, required this.size});

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
    final image = _resolve(url);
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

/// 评论输入弹层.
class _InputSheet extends StatefulWidget {
  const _InputSheet({this.hint});

  final String? hint;

  @override
  State<_InputSheet> createState() => _InputSheetState();
}

class _InputSheetState extends State<_InputSheet> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      return;
    }
    Navigator.of(context).pop(text);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                autofocus: true,
                minLines: 1,
                maxLines: 4,
                maxLength: 500,
                buildCounter:
                    (
                      context, {
                      required currentLength,
                      required isFocused,
                      maxLength,
                    }) => null,
                decoration: InputDecoration(hintText: widget.hint ?? '说点什么'),
                style: const TextStyle(fontSize: 14),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(onPressed: _submit, child: const Text('发送')),
          ],
        ),
      ),
    );
  }
}

/// 头像地址补全, 站点偶尔返回相对路径.
String _resolve(String raw) {
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

/// 去掉异常前缀, 让提示可读.
String? _cleanError(String? raw) {
  if (raw == null) {
    return null;
  }
  var text = raw.trim();
  if (text.isEmpty) {
    return null;
  }
  for (final prefix in ['Exception: ', 'DioException ', 'FormatException: ']) {
    if (text.startsWith(prefix)) {
      text = text.substring(prefix.length);
    }
  }
  if (text.startsWith('[')) {
    final end = text.indexOf(']');
    if (end > 0) {
      text = text.substring(end + 1).trim();
    }
  }
  return text.isEmpty ? null : text;
}
