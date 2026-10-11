import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tucao/common/widgets/loading_widget.dart';
import 'package:tucao/http/message_http.dart';
import 'package:tucao/models/message.dart';
import 'package:tucao/services/account_service.dart';
import 'package:tucao/utils/logger.dart';

/// 私信会话控制器.
class MessageController extends GetxController {
  MessageController(this.messageId);

  final String messageId;

  final list = <MessageDetail>[].obs;

  final firstLoading = true.obs;

  final error = RxnString();

  final sending = false.obs;

  @override
  void onInit() {
    super.onInit();
    load();
  }

  String get selfUid => AccountService.instance.user.value?.userId.toString() ?? '';

  Future<void> load() async {
    firstLoading.value = true;
    error.value = null;
    try {
      if (AccountService.instance.user.value == null) {
        error.value = '请先登录后查看私信';
        return;
      }
      final result = await MessageHttp.detail(
        messageId: messageId,
        selfUid: selfUid,
      );
      list.assignAll(result);
    } catch (e, stackTrace) {
      Log.e('加载私信详情失败', error: e, stackTrace: stackTrace);
      error.value = e.toString();
    } finally {
      firstLoading.value = false;
    }
  }

  @override
  Future<void> refresh() => load();

  /// 回复当前会话, 成功返回空, 失败返回提示文本.
  Future<String?> reply(String content, String toUserId, String subject) async {
    final text = content.trim();
    if (text.isEmpty) {
      return '回复内容不能为空';
    }
    sending.value = true;
    try {
      final result = await MessageHttp.reply(
        replyId: messageId,
        toUserId: toUserId,
        subject: subject,
        content: text,
      );
      if (result == null) {
        await load();
      }
      return result;
    } catch (e, stackTrace) {
      Log.e('回复私信失败', error: e, stackTrace: stackTrace);
      return '回复失败, 请稍后重试';
    } finally {
      sending.value = false;
    }
  }
}

/// 私信会话页面.
class MessagePage extends StatefulWidget {
  const MessagePage({super.key, required this.messageId, this.userName = ''});

  final String messageId;

  /// 对方昵称, 用于标题展示.
  final String userName;

  @override
  State<MessagePage> createState() => _MessagePageState();
}

class _MessagePageState extends State<MessagePage> {
  late final String _tag = 'message_${identityHashCode(this)}';

  late final MessageController _controller = Get.put(
    MessageController(widget.messageId),
    tag: _tag,
  );

  final _input = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    if (Get.isRegistered<MessageController>(tag: _tag)) {
      Get.delete<MessageController>(tag: _tag);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.userName.isEmpty ? '私信' : widget.userName),
      ),
      body: Column(
        children: [
          Expanded(child: _buildBody()),
          // 未登录时不给输入框, 避免发送必然失败.
          if (AccountService.instance.isLogin) _buildInput(context),
        ],
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
        return ErrorWidgetView(message: error, onRetry: _controller.load);
      }
      final list = _controller.list;
      return RefreshIndicator(
        onRefresh: _controller.refresh,
        child: ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(vertical: 10),
          itemCount: list.length,
          itemBuilder: (context, index) => _MessageBubble(item: list[index]),
        ),
      );
    });
  }

  Widget _buildInput(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: scheme.outlineVariant, width: 0.5),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _input,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.newline,
                decoration: const InputDecoration(
                  hintText: '输入回复内容',
                  isDense: true,
                  border: InputBorder.none,
                ),
              ),
            ),
            Obx(
              () => IconButton(
                onPressed: _controller.sending.value ? null : _send,
                icon: _controller.sending.value
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send),
                tooltip: '发送',
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 会话里对方的 uid, 取最后一条对方消息的发送者.
  String get _peerUid {
    for (final item in _controller.list.reversed) {
      if (!item.isMine && item.userId.isNotEmpty) {
        return item.userId;
      }
    }
    return '';
  }

  Future<void> _send() async {
    final peerUid = _peerUid;
    if (peerUid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('找不到对方账号, 无法回复')),
      );
      return;
    }
    final subject = widget.userName.isEmpty ? '回复' : '回复: ${widget.userName}';
    final result = await _controller.reply(_input.text, peerUid, subject);
    if (!mounted) {
      return;
    }
    if (result != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result)),
      );
      return;
    }
    _input.clear();
  }
}

/// 一条会话消息, 自己的靠右, 对方的靠左.
class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.item});

  final MessageDetail item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final bubbleColor = item.isMine
        ? scheme.primaryContainer
        : scheme.surfaceContainerHighest;
    final textColor = item.isMine
        ? scheme.onPrimaryContainer
        : scheme.onSurface;

    final bubble = Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width * 0.72,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bubbleColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        item.content,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: textColor,
          height: 1.4,
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Column(
        crossAxisAlignment: item.isMine
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: item.isMine
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!item.isMine) ...[
                _Avatar(url: item.avatar),
                const SizedBox(width: 8),
              ],
              Flexible(child: bubble),
              if (item.isMine) ...[
                const SizedBox(width: 8),
                _Avatar(url: item.avatar),
              ],
            ],
          ),
          if (item.time.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                item.time,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ClipOval(
      child: SizedBox(
        width: 32,
        height: 32,
        child: url.isEmpty
            ? ColoredBox(
                color: scheme.surfaceContainerHighest,
                child: Icon(
                  Icons.person,
                  size: 16,
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
                    Icons.person,
                    size: 16,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
      ),
    );
  }
}
