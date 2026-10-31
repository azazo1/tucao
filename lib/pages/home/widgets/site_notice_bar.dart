import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tucao/http/site_notice_http.dart';
import 'package:tucao/router/routes.dart';
import 'package:tucao/services/site_notice_service.dart';
import 'package:tucao/utils/logger.dart';

void _openNotice(SiteNotice notice) {
  Log.i('打开首页站务文章: ${notice.title}');
  Get.toNamed(Routes.article, parameters: {'hid': notice.hid});
}

/// 首页主标签栏上方的通知卡片, 带封面缩略图, 轮换站务文章.
///
/// 每 [interval] 自动切到下一篇, 也可以左右滑动切换, 手指拖动期间暂停自动切换.
/// 点卡片打开文章, 关掉后本次运行内不再显示.
/// 卡片挂在顶栏的 bottom 里, 顶栏需要固定高度, 因此高度固定为 [height],
/// 是否占位由 [visible] 决定.
class SiteNoticeBar extends StatefulWidget {
  const SiteNoticeBar({super.key});

  static const interval = Duration(seconds: 5);

  /// 含上下留白的总高度.
  static const height = 72.0;

  /// 是否显示通知卡片, 在 Obx 里调用才会跟着变化.
  static bool get visible =>
      Get.isRegistered<SiteNoticeService>() &&
      SiteNoticeService.instance.visible;

  @override
  State<SiteNoticeBar> createState() => _SiteNoticeBarState();
}

class _SiteNoticeBarState extends State<SiteNoticeBar> {
  /// 页码从一个足够大的值开始, 向左向右都能一直滑, 显示时再对篇数取模.
  static const _startPage = 10000;

  final _pageController = PageController(initialPage: _startPage);
  Timer? _timer;
  int _page = _startPage;
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    _restartTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  void _restartTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(SiteNoticeBar.interval, (_) => _next());
  }

  void _next() {
    if (!mounted || _dragging || !_pageController.hasClients) {
      return;
    }
    if (SiteNoticeService.instance.notices.length < 2) {
      return;
    }
    final target = _page + 1;
    if (MediaQuery.disableAnimationsOf(context)) {
      _pageController.jumpToPage(target);
    } else {
      _pageController.animateToPage(
        target,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  /// 手指拖动时暂停自动切换, 松手停稳后重新计时, 免得刚滑到一篇马上被切走.
  bool _onScroll(ScrollNotification notification) {
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      _dragging = true;
      _timer?.cancel();
    } else if (notification is ScrollEndNotification && _dragging) {
      _dragging = false;
      _restartTimer();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    if (!Get.isRegistered<SiteNoticeService>()) {
      return const SizedBox.shrink();
    }
    final service = SiteNoticeService.instance;
    return Obx(() {
      if (!service.visible) {
        return const SizedBox.shrink();
      }
      return _build(service, service.notices.toList());
    });
  }

  Widget _build(SiteNoticeService service, List<SiteNotice> notices) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final single = notices.length < 2;
    return SizedBox(
      height: SiteNoticeBar.height,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
        child: Material(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(10),
          clipBehavior: Clip.antiAlias,
          child: Row(
            children: [
              Expanded(
                child: NotificationListener<ScrollNotification>(
                  onNotification: _onScroll,
                  child: PageView.builder(
                    controller: _pageController,
                    physics: single
                        ? const NeverScrollableScrollPhysics()
                        : null,
                    onPageChanged: (page) => setState(() => _page = page),
                    itemBuilder: (context, page) {
                      final notice = notices[page % notices.length];
                      return InkWell(
                        onTap: () => _openNotice(notice),
                        child: _NoticeContent(notice: notice),
                      );
                    },
                  ),
                ),
              ),
              if (!single)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Text(
                    '${_page % notices.length + 1}/${notices.length}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              IconButton(
                onPressed: service.dismiss,
                tooltip: '关闭通知',
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  Icons.close,
                  size: 16,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 通知卡片里的一页: 竖版封面缩略图, 标题与一行摘要.
class _NoticeContent extends StatelessWidget {
  const _NoticeContent({required this.notice});

  final SiteNotice notice;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final placeholder = ColoredBox(color: scheme.surfaceContainerHighest);
    return Row(
      children: [
        SizedBox(
          width: 46,
          height: double.infinity,
          child: notice.cover.isEmpty
              ? placeholder
              : CachedNetworkImage(
                  imageUrl: notice.cover,
                  fit: BoxFit.cover,
                  errorWidget: (context, url, error) => placeholder,
                ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                notice.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (notice.summary.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  notice.summary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
