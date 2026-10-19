import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tucao/common/widgets/loading_widget.dart';
import 'package:tucao/http/message_http.dart';
import 'package:tucao/models/message.dart';
import 'package:tucao/router/routes.dart';
import 'package:tucao/services/account_service.dart';
import 'package:tucao/utils/logger.dart';

/// 系统公告控制器.
class SystemListController extends GetxController {
  final list = <SystemMessage>[].obs;

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
        error.value = '请先登录后查看系统消息';
        return;
      }
      final result = await MessageHttp.groupList();
      list.assignAll(result);
    } catch (e, stackTrace) {
      Log.e('加载系统公告失败', error: e, stackTrace: stackTrace);
      error.value = e.toString();
    } finally {
      firstLoading.value = false;
    }
  }

  @override
  Future<void> refresh() => load();
}

/// 系统公告列表, 作为私信页里的第二个标签.
class SystemListView extends StatefulWidget {
  const SystemListView({super.key});

  @override
  State<SystemListView> createState() => _SystemListViewState();
}

class _SystemListViewState extends State<SystemListView> {
  late final String _tag = 'system_list_${identityHashCode(this)}';

  late final SystemListController _controller = Get.put(
    SystemListController(),
    tag: _tag,
  );

  @override
  void dispose() {
    if (Get.isRegistered<SystemListController>(tag: _tag)) {
      Get.delete<SystemListController>(tag: _tag);
    }
    super.dispose();
  }

  /// 打开公告, 回来后重新拉一次列表, 让站点刚清掉的未读标记跟着消失.
  Future<void> _open(SystemMessage item) async {
    await Get.toNamed(Routes.systemMessage, parameters: {'id': item.id});
    if (mounted) {
      await _controller.load();
    }
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
        return const EmptyWidget(message: '还没有收到系统消息');
      }
      return RefreshIndicator(
        onRefresh: _controller.refresh,
        child: ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          itemCount: _controller.list.length,
          separatorBuilder: (context, index) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final item = _controller.list[index];
            return _SystemTile(item: item, onTap: () => _open(item));
          },
        ),
      );
    });
  }
}

/// 一条系统公告摘要.
///
/// 站点列表里只有发送者 SYSTEM 与整段摘要, 标题写在摘要第一行, 解析时已经
/// 拆开, 这里把标题加粗单独放一行.
class _SystemTile extends StatelessWidget {
  const _SystemTile({required this.item, required this.onTap});

  final SystemMessage item;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return InkWell(
      onTap: onTap,
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
                          Icons.campaign_outlined,
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
                            Icons.campaign_outlined,
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
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (item.unread) ...[
                        const SizedBox(width: 6),
                        const _UnreadBadge(),
                      ],
                      if (item.time.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Text(
                          item.time,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (item.summary.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      item.summary,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
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
}

/// 未读标记, 站点在未读的条目上用同样的描边胶囊.
class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        border: Border.all(color: scheme.primary),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '未读',
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: scheme.primary),
      ),
    );
  }
}
