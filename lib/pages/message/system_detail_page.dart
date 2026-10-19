import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tucao/common/adaptive.dart';
import 'package:tucao/common/widgets/loading_widget.dart';
import 'package:tucao/http/message_http.dart';
import 'package:tucao/models/message.dart';
import 'package:tucao/pages/mine/image_viewer_page.dart';
import 'package:tucao/services/account_service.dart';
import 'package:tucao/utils/logger.dart';
import 'package:tucao/utils/site_url.dart';
import 'package:url_launcher/url_launcher.dart';

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
/// 宽度铺开, 链接点开走系统浏览器. 站点的页面是桌面布局, 直接塞进 WebView
/// 只会得到一个缩小的网页, 与应用的字体, 配色和深色模式都对不上.
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
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            for (final block in detail.blocks) _buildBlock(block),
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
      );
    });
  }

  Widget _buildBlock(SystemContentBlock block) {
    return switch (block) {
      SystemParagraph(:final parts) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: _ParagraphText(parts: parts),
      ),
      SystemImage(:final url) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: _AnnouncementImage(url: url),
      ),
    };
  }
}

/// 公告正文里的段落, 链接单独上色并可点击.
class _ParagraphText extends StatefulWidget {
  const _ParagraphText({required this.parts});

  final List<SystemTextPart> parts;

  @override
  State<_ParagraphText> createState() => _ParagraphTextState();
}

class _ParagraphTextState extends State<_ParagraphText> {
  /// 与 [widget.parts] 一一对应的链接手势, 只有链接位置非空.
  ///
  /// 手势识别器要自己回收, 因此跟随后缀一起在这里维护, 不在 build 里新建.
  final _recognizers = <TapGestureRecognizer?>[];

  @override
  void initState() {
    super.initState();
    _buildRecognizers();
  }

  @override
  void didUpdateWidget(covariant _ParagraphText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.parts, widget.parts)) {
      _releaseRecognizers();
      _buildRecognizers();
    }
  }

  @override
  void dispose() {
    _releaseRecognizers();
    super.dispose();
  }

  void _buildRecognizers() {
    for (final part in widget.parts) {
      final url = part.url;
      _recognizers.add(
        url == null || url.isEmpty
            ? null
            : (TapGestureRecognizer()..onTap = () => _open(url)),
      );
    }
  }

  void _releaseRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer?.dispose();
    }
    _recognizers.clear();
  }

  Future<void> _open(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) {
      return;
    }
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e, stackTrace) {
      Log.e('打开公告里的链接失败', error: e, stackTrace: stackTrace);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final linkStyle = TextStyle(
      color: scheme.primary,
      decoration: TextDecoration.underline,
      decorationColor: scheme.primary,
    );
    return Text.rich(
      TextSpan(
        children: [
          for (var index = 0; index < widget.parts.length; index++)
            TextSpan(
              text: widget.parts[index].text,
              style: _recognizers[index] == null ? null : linkStyle,
              recognizer: _recognizers[index],
            ),
        ],
      ),
      style: theme.textTheme.bodyMedium?.copyWith(
        height: 1.6,
        color: scheme.onSurface,
      ),
    );
  }
}

/// 公告正文里的图片.
///
/// 按内容宽度铺开, 点开进入全屏查看, 缩放与保存交给查看页. 站外图片不自动
/// 联网, 与评论里的图片同一套规则, 免得公告里塞的外部地址在列表滚动时就
/// 让本机发请求.
class _AnnouncementImage extends StatefulWidget {
  const _AnnouncementImage({required this.url});

  final String url;

  @override
  State<_AnnouncementImage> createState() => _AnnouncementImageState();
}

class _AnnouncementImageState extends State<_AnnouncementImage> {
  late bool _allowed = isSiteImage(widget.url);

  void _open() {
    Get.to(
      () => ImageViewerPage(
        url: widget.url,
        title: '系统公告图片',
        prefix: 'tucao-message',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (!_allowed) {
      return InkWell(
        onTap: () => setState(() => _allowed = true),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: 120,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '站外图片, 点击加载',
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
        ),
      );
    }
    final cacheWidth =
        (MediaQuery.sizeOf(context).width *
                MediaQuery.devicePixelRatioOf(context))
            .round();
    return GestureDetector(
      onTap: _open,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: CachedNetworkImage(
          imageUrl: widget.url,
          width: double.infinity,
          fit: BoxFit.fitWidth,
          memCacheWidth: cacheWidth,
          placeholder: (context, url) => _placeholder(scheme),
          errorWidget: (context, url, error) => Container(
            height: 120,
            alignment: Alignment.center,
            color: scheme.surfaceContainerHighest,
            child: Icon(
              Icons.broken_image_outlined,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }

  Widget _placeholder(ColorScheme scheme) => Container(
    height: 120,
    color: scheme.surfaceContainerHighest,
  );
}
