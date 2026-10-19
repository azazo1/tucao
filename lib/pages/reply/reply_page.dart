import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tucao/common/adaptive.dart';
import 'package:tucao/common/widgets/paging_list.dart';
import 'package:tucao/models/reply.dart';
import 'package:tucao/pages/reply/reply_controller.dart';
import 'package:tucao/pages/reply/widgets/comment_tile.dart';
import 'package:tucao/pages/reply/widgets/reply_input_sheet.dart';
import 'package:tucao/pages/reply/widgets/reply_thread_view.dart';
import 'package:tucao/services/account_service.dart';
import 'package:tucao/services/vip_service.dart';

/// 独立评论入口, 视频页直接使用 [ReplyPanel].
class ReplyPage extends StatelessWidget {
  const ReplyPage({
    super.key,
    required this.typeId,
    required this.hid,
    this.part = 0,
  });

  final int typeId;
  final String hid;
  final int part;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('评论')),
      body: ReplyPanel(typeId: typeId, hid: hid, part: part),
    );
  }
}

/// 不带页面外壳的评论面板, 每个实例拥有自己的控制器.
class ReplyPanel extends StatefulWidget {
  const ReplyPanel({
    super.key,
    required this.typeId,
    required this.hid,
    this.part = 0,
    this.controllerFactory,
  });

  /// 视频所在分区, 与 hid 一起构成评论楼层 id.
  final int typeId;
  final String hid;

  /// 当前分 P, 不参与评论控制器的身份.
  final int part;

  /// 允许测试注入无网络控制器, 所有权仍属于面板.
  final ReplyController Function(int typeId, String hid, int part)?
  controllerFactory;

  @override
  State<ReplyPanel> createState() => _ReplyPanelState();
}

class _ReplyPanelState extends State<ReplyPanel>
    with AutomaticKeepAliveClientMixin {
  late ReplyController controller;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _createController();
  }

  void _createController() {
    controller =
        widget.controllerFactory?.call(
          widget.typeId,
          widget.hid,
          widget.part,
        ) ??
        ReplyController(
          typeId: widget.typeId,
          hid: widget.hid,
          part: widget.part,
        );
    // 不注册到全局 Get, 避免重复打开视频时共享或删除别的面板.
    controller.onStart();
  }

  @override
  void didUpdateWidget(covariant ReplyPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.hid != widget.hid || oldWidget.typeId != widget.typeId) {
      controller.onDelete();
      _createController();
    }
  }

  @override
  void dispose() {
    controller.onDelete();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(13) / 13;
        final inputHeight = (56 * scale + MediaQuery.paddingOf(context).bottom)
            .clamp(0.0, constraints.maxHeight / 2);
        return AdaptiveBody(
          child: Column(
            children: [
              Expanded(
                child: Obx(() {
                  // toList 会读取响应式列表, 让刷新与分页结果重建列表.
                  final comments = controller.list.toList();
                  return PagingList<ReplyModel>(
                    key: ValueKey(controller),
                    list: comments,
                    itemBuilder: _buildItem,
                    onRefresh: controller.refresh,
                    onLoadMore: controller.loadMore,
                    hasMore: controller.hasMore,
                    loading: controller.loading.value,
                    firstLoading: controller.firstLoading.value,
                    error: cleanReplyError(controller.error.value),
                    onRetry: controller.loadFirst,
                    emptyMessage: '还没有评论, 来说点什么吧',
                    separator: const Divider(),
                  );
                }),
              ),
              SizedBox(
                height: inputHeight,
                child: SingleChildScrollView(child: _buildInputBar(context)),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildItem(BuildContext context, ReplyModel comment, int index) {
    return Obx(() {
      final thread = controller.threadOf(comment.id);
      final expanded = controller.expanded.contains(comment.id);
      final count = controller.replyCount(comment);
      final Widget? footer;
      if (expanded) {
        footer = ReplyThreadView(
          commentId: comment.id,
          thread: thread,
          count: count,
          hasMore: controller.hasMoreReplies(comment),
          supportCountOf: controller.supportCount,
          isSupported: (reply) => controller.isSupported(reply.id),
          onCollapse: () => _collapse(comment),
          onLoadMore: () => _loadMore(comment),
          onRetry: () => _retry(comment),
          onSupport: _support,
          onReply: (reply) => _openInput(replyTo: reply),
          isVipOf: _isVipOf,
        );
      } else if (count > 0 || thread.error != null) {
        footer = ReplyExpandButton(
          commentId: comment.id,
          count: count,
          loading: thread.loading,
          failed: thread.error != null,
          onTap: () => _toggle(comment),
        );
      } else {
        footer = null;
      }
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: CommentTile(
          comment: comment,
          // 会员标记来自两处: 评论 json 里评论者没设昵称时连带返回的用户记录,
          // 以及按页抓回来的评论页颜色, 见 VipService.
          isVip: comment.isVip || _isVipOf(comment.userId),
          supportCount: controller.supportCount(comment),
          supported: controller.isSupported(comment.id),
          onSupport: () => _support(comment),
          onReply: () => _openInput(replyTo: comment),
          footer: footer,
        ),
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
                constraints: const BoxConstraints(minHeight: 38),
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
                    Expanded(
                      child: Text(
                        sending ? '正在发送' : '说点什么',
                        style: TextStyle(
                          fontSize: 13,
                          color: scheme.onSurfaceVariant,
                        ),
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

  /// 评论者是否是已知的破会员.
  ///
  /// 在 Obx 里调用, 标记到位后昵称颜色会自己更新.
  bool _isVipOf(int uid) => VipService.maybe?.isVip(uid) ?? false;

  /// 展开或收起楼中楼.
  Future<void> _toggle(ReplyModel comment) async {
    try {
      await controller.toggleReplies(comment);
    } catch (e) {
      _toast(cleanReplyError(e.toString()) ?? '加载回复失败');
    }
  }

  /// 收起楼中楼, 不丢弃已加载的数据, 再次展开时直接显示.
  void _collapse(ReplyModel comment) {
    controller.collapseReplies(comment);
  }

  /// 加载楼中楼的后续页.
  Future<void> _loadMore(ReplyModel comment) async {
    try {
      await controller.loadMoreReplies(comment);
    } catch (e) {
      _toast(cleanReplyError(e.toString()) ?? '加载更多回复失败');
    }
  }

  /// 失败后重试当前楼中楼.
  Future<void> _retry(ReplyModel comment) async {
    try {
      await controller.retryReplies(comment);
    } catch (e) {
      _toast(cleanReplyError(e.toString()) ?? '加载回复失败');
    }
  }

  Future<void> _support(ReplyModel comment) async {
    try {
      await controller.support(comment);
    } catch (e) {
      _toast(cleanReplyError(e.toString()) ?? '点赞失败');
    }
  }

  /// 弹出输入框, 发送评论或回复.
  Future<void> _openInput({ReplyModel? replyTo}) async {
    if (!AccountService.instance.isLogin) {
      _toast('请先登录');
      return;
    }
    final inputController = controller;
    final text = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => ReplyInputSheet(
        replyToName: replyTo?.userName,
        // 站点网页端只有一级评论的输入框带图片按钮, 楼中楼回复不提供图评,
        // 这里保持一致, 免得传上一张图才被站点拒掉.
        onUploadImage: replyTo != null
            ? null
            : (bytes, fileName) =>
                  inputController.uploadImage(bytes: bytes, fileName: fileName),
        imageEnabled: AccountService.instance.user.value?.isVip ?? false,
      ),
    );
    if (!mounted ||
        !identical(controller, inputController) ||
        inputController.isClosed ||
        text == null ||
        text.trim().isEmpty) {
      return;
    }
    try {
      await inputController.send(text, replyTo: replyTo);
      _toast(replyTo == null ? '评论成功' : '回复成功');
    } catch (e) {
      _toast(cleanReplyError(e.toString()) ?? '发送失败');
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
