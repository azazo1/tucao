import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tucao/common/adaptive.dart';
import 'package:tucao/common/widgets/loading_widget.dart';
import 'package:tucao/http/life_http.dart';
import 'package:tucao/models/life.dart';
import 'package:tucao/pages/life/widgets/life_rank_tile.dart';
import 'package:tucao/router/routes.dart';
import 'package:tucao/utils/logger.dart';

/// 贡献榜控制器.
class LifeRankController extends GetxController {
  final rank = Rxn<LifeRank>();

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
      rank.value = await LifeHttp.fetchRank();
    } catch (e, stackTrace) {
      Log.e('加载贡献榜失败', error: e, stackTrace: stackTrace);
      error.value = e.toString();
    } finally {
      firstLoading.value = false;
    }
  }

  @override
  Future<void> refresh() => load();
}

/// 贡献榜页面.
///
/// 榜单列的是各用户为站点续命的天数, 站点按广告收益折算, 榜单上不带头像
/// 之外的用户信息, 因此条目不可点.
class LifeRankPage extends StatefulWidget {
  const LifeRankPage({super.key});

  @override
  State<LifeRankPage> createState() => _LifeRankPageState();
}

class _LifeRankPageState extends State<LifeRankPage> {
  late final String _tag = 'life_rank_${identityHashCode(this)}';

  late final LifeRankController _controller = Get.put(
    LifeRankController(),
    tag: _tag,
  );

  @override
  void dispose() {
    if (Get.isRegistered<LifeRankController>(tag: _tag)) {
      Get.delete<LifeRankController>(tag: _tag);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('贡献榜')),
      body: Obx(() {
        if (_controller.firstLoading.value) {
          return const LoadingWidget();
        }
        final error = _controller.error.value;
        if (error != null) {
          return ErrorWidgetView(message: error, onRetry: _controller.load);
        }
        final rank = _controller.rank.value ?? const LifeRank(items: []);
        final maxRatio = _maxRatio(rank.items);
        return RefreshIndicator(
          onRefresh: _controller.refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.symmetric(
              horizontal: Adaptive.sidePadding(context),
            ),
            children: [
              if (rank.requiresLogin)
                Padding(
                  padding: const EdgeInsets.only(top: 80),
                  child: EmptyWidget(
                    message: '登录后可以查看贡献榜',
                    icon: Icons.lock_outline,
                    retryText: '去登录',
                    onRetry: () => Get.toNamed(Routes.login),
                  ),
                )
              else if (rank.items.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 80),
                  child: EmptyWidget(message: '这个榜单还没有内容'),
                )
              else ...[
                for (var i = 0; i < rank.items.length; i++) ...[
                  if (i > 0) const Divider(),
                  LifeRankTile(item: rank.items[i], maxRatio: maxRatio),
                ],
                const SizedBox(height: 8),
                _sourceLink(rank),
                const SizedBox(height: 16),
              ],
            ],
          ),
        );
      }),
    );
  }

  /// 榜单里最大的占比, 用来把站点的小数百分比放大成整条长度.
  ///
  /// 站点是按占比排序的, 正常情况榜首就是最大值.
  static double _maxRatio(List<LifeRankItem> items) {
    var max = 0.0;
    for (final item in items) {
      if (item.ratio > max) {
        max = item.ratio;
      }
    }
    return max;
  }

  /// 页脚的来源说明, 指向站点解释续命规则的公告.
  Widget _sourceLink(LifeRank rank) {
    const label = '数据来源AD';
    final scheme = Theme.of(context).colorScheme;
    if (rank.sourceArticleId.isEmpty) {
      return Center(
        child: Text(
          label,
          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
        ),
      );
    }
    return Center(
      child: TextButton(
        onPressed: () => Get.toNamed(
          Routes.article,
          parameters: {'hid': rank.sourceArticleId},
        ),
        child: const Text(label, style: TextStyle(fontSize: 12)),
      ),
    );
  }
}
