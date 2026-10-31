import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tucao/common/adaptive.dart';
import 'package:tucao/common/rich_html/rich_content.dart';
import 'package:tucao/common/rich_html/rich_content_view.dart';
import 'package:tucao/common/widgets/copy_selection_area.dart';
import 'package:tucao/common/widgets/loading_widget.dart';
import 'package:tucao/http/message_http.dart';
import 'package:tucao/models/message.dart';
import 'package:tucao/services/account_service.dart';
import 'package:tucao/utils/logger.dart';

/// 系统公告详情控制器.
class SystemDetailController extends GetxController {
  SystemDetailController(this.groupId);

  final String groupId;

  final detail = Rxn<SystemMessageDetail>();

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
      if (!AccountService.instance.isLogin) {
        error.value = '请先登录后查看系统消息';
        return;
      }
      detail.value = await MessageHttp.groupDetail(groupId: groupId);
    } catch (e, stackTrace) {
      Log.e('加载系统公告详情失败', error: e, stackTrace: stackTrace);
      error.value = e.toString();
    } finally {
      firstLoading.value = false;
    }
  }

  @override
  Future<void> refresh() => load();
}

/// 系统公告详情页.
///
/// 正文由站点以富文本给出, 这里用原生组件按块渲染: 段落是文本, 图片按内容
/// 宽度铺开, 链接点开走站内页面或系统浏览器. 站点的页面是桌面布局, 直接塞进
/// WebView 只会得到一个缩小的网页, 与应用的字体, 配色和深色模式都对不上.
class SystemDetailPage extends StatefulWidget {
  const SystemDetailPage({super.key, required this.groupId});

  final String groupId;

  @override
  State<SystemDetailPage> createState() => _SystemDetailPageState();
}

class _SystemDetailPageState extends State<SystemDetailPage> {
  late final String _tag = 'system_detail_${identityHashCode(this)}';

  late final SystemDetailController _controller = Get.put(
    SystemDetailController(widget.groupId),
    tag: _tag,
  );

  @override
  void dispose() {
    if (Get.isRegistered<SystemDetailController>(tag: _tag)) {
      Get.delete<SystemDetailController>(tag: _tag);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Obx(() {
          final title = _controller.detail.value?.title ?? '';
          return Text(
            title.isEmpty ? '系统消息' : title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          );
        }),
      ),
      body: AdaptiveBody(child: _buildBody(context)),
    );
  }

  Widget _buildBody(BuildContext context) {
    return Obx(() {
      if (_controller.firstLoading.value) {
        return const LoadingWidget();
      }
      final detail = _controller.detail.value;
      if (detail == null) {
        return ErrorWidgetView(
          message: _controller.error.value ?? '没有取到内容',
          onRetry: _controller.load,
        );
      }
      final theme = Theme.of(context);
      return RefreshIndicator(
        onRefresh: _controller.refresh,
        child: CopySelectionArea(
          // 图片与时间不进入剪贴板, 标题也不包含, 只保留段落文字.
          text: richPlainText(detail.blocks),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              RichContentView(
                blocks: detail.blocks,
                imageTitle: '系统公告图片',
                imagePrefix: 'tucao-message',
              ),
              if (detail.time.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  detail.time,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    });
  }
}
