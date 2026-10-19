import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tucao/common/widgets/loading_widget.dart';
import 'package:tucao/http/message_http.dart';
import 'package:tucao/models/message.dart';
import 'package:tucao/router/routes.dart';
import 'package:tucao/services/account_service.dart';
import 'package:tucao/utils/logger.dart';

/// 收件箱控制器.
class InboxController extends GetxController {
  final list = <MessageModel>[].obs;

  final firstLoading = true.obs;

  final error = RxnString();

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
        error.value = '请先登录后查看私信';
        return;
      }
      final result = await MessageHttp.inbox();
      list.assignAll(result);
    } catch (e, stackTrace) {
      Log.e('加载收件箱失败', error: e, stackTrace: stackTrace);
      error.value = e.toString();
    } finally {
      firstLoading.value = false;
    }
  }

  @override
  Future<void> refresh() => load();
}

/// 收件箱列表, 作为私信页里的第一个标签.
class InboxView extends StatefulWidget {
  const InboxView({super.key});

  @override
  State<InboxView> createState() => _InboxViewState();
}

class _InboxViewState extends State<InboxView> {
  late final String _tag = 'inbox_${identityHashCode(this)}';

  late final InboxController _controller = Get.put(
    InboxController(),
    tag: _tag,
  );

  @override
  void dispose() {
    if (Get.isRegistered<InboxController>(tag: _tag)) {
      Get.delete<InboxController>(tag: _tag);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (_controller.firstLoading.value) {
        return const LoadingWidget();
      }
      final error = _controller.error.value;
      if (error != null && _controller.list.isEmpty) {
        return ErrorWidgetView(message: error, onRetry: _controller.load);
      }
      if (_controller.list.isEmpty) {
        return const EmptyWidget(message: '还没有收到私信');
      }
      return RefreshIndicator(
        onRefresh: _controller.refresh,
        child: ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          itemCount: _controller.list.length,
          separatorBuilder: (context, index) => const Divider(height: 1),
          itemBuilder: (context, index) =>
              _InboxTile(item: _controller.list[index]),
        ),
      );
    });
  }
}

/// 一条私信摘要.
class _InboxTile extends StatelessWidget {
  const _InboxTile({required this.item});

  final MessageModel item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return InkWell(
      onTap: () => Get.toNamed(
        Routes.message,
        parameters: {'id': item.id},
        // 昵称可能含中文与特殊字符, 走 arguments 而不是 url 参数.
        arguments: item.username,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipOval(
              child: SizedBox(
                width: 40,
                height: 40,
                child: item.avatar.isEmpty
                    ? ColoredBox(
                        color: scheme.surfaceContainerHighest,
                        child: Icon(
                          Icons.person,
                          size: 20,
                          color: scheme.onSurfaceVariant,
                        ),
                      )
                    : CachedNetworkImage(
                        imageUrl: item.avatar,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => ColoredBox(
                          color: scheme.surfaceContainerHighest,
                        ),
                        errorWidget: (context, url, error) => ColoredBox(
                          color: scheme.surfaceContainerHighest,
                          child: Icon(
                            Icons.person,
                            size: 20,
                            color: scheme.onSurfaceVariant,
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
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.username,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (item.time.isNotEmpty)
                        Text(
                          item.time,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.message,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
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
