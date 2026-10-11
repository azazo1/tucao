import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tucao/common/widgets/channel_bar.dart';
import 'package:tucao/common/widgets/loading_widget.dart';
import 'package:tucao/http/user_rank_http.dart';
import 'package:tucao/router/routes.dart';
import 'package:tucao/utils/logger.dart';

/// u榜页面控制器.
class UserRankController extends GetxController {
  final groups = <UserRankGroup>[].obs;

  final index = 0.obs;

  final firstLoading = true.obs;

  final error = RxnString();

  /// 当前分组的条目, 没有数据时返回空列表.
  List<UserRankItem> get list {
    if (groups.isEmpty) {
      return const [];
    }
    return groups[index.value.clamp(0, groups.length - 1)].list;
  }

  @override
  void onInit() {
    super.onInit();
    load();
  }

  Future<void> load() async {
    firstLoading.value = true;
    error.value = null;
    try {
      final result = await UserRankHttp.fetch();
      groups.assignAll(result);
      index.value = 0;
    } catch (e, stackTrace) {
      Log.e('加载 u榜失败', error: e, stackTrace: stackTrace);
      error.value = e.toString();
    } finally {
      firstLoading.value = false;
    }
  }

  @override
  Future<void> refresh() => load();

  void changeGroup(int value) {
    if (value >= 0 && value < groups.length) {
      index.value = value;
    }
  }
}

/// u榜页面.
///
/// 该榜单列的是用户, 点按进入用户空间.
class UserRankPage extends StatefulWidget {
  const UserRankPage({super.key});

  @override
  State<UserRankPage> createState() => _UserRankPageState();
}

class _UserRankPageState extends State<UserRankPage> {
  late final String _tag = 'user_rank_${identityHashCode(this)}';

  late final UserRankController _controller = Get.put(
    UserRankController(),
    tag: _tag,
  );

  @override
  void dispose() {
    if (Get.isRegistered<UserRankController>(tag: _tag)) {
      Get.delete<UserRankController>(tag: _tag);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('u榜')),
      body: Obx(() {
        if (_controller.firstLoading.value) {
          return const LoadingWidget();
        }
        final error = _controller.error.value;
        if (error != null) {
          return ErrorWidgetView(message: error, onRetry: _controller.load);
        }
        final groups = _controller.groups;
        return Column(
          children: [
            if (groups.length > 1)
              ChannelBar(
                channels: [
                  for (var i = 0; i < groups.length; i++)
                    ChannelItem(id: i, name: groups[i].title),
                ],
                currentId: _controller.index.value,
                onChanged: (value) {
                  if (value != null) {
                    _controller.changeGroup(value);
                  }
                },
              ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _controller.refresh,
                child: _controller.list.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: const [
                          SizedBox(height: 120),
                          EmptyWidget(message: '这个榜单还没有内容'),
                        ],
                      )
                    : ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        itemCount: _controller.list.length,
                        separatorBuilder: (context, index) => const Divider(),
                        itemBuilder: (context, index) =>
                            _UserRankTile(item: _controller.list[index]),
                      ),
              ),
            ),
          ],
        );
      }),
    );
  }
}

/// 一条用户榜记录.
class _UserRankTile extends StatelessWidget {
  const _UserRankTile({required this.item});

  final UserRankItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final highlight = item.rank <= 3;
    return InkWell(
      onTap: () => Get.toNamed(
        Routes.space,
        parameters: {'uid': item.userId.toString()},
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            SizedBox(
              width: 28,
              child: Text(
                '${item.rank}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: highlight ? scheme.primary : scheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(width: 8),
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
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                item.userName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium,
              ),
            ),
            if (item.badge.isNotEmpty)
              Text(
                item.badge,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
