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

  /// 通知列表变化时预加载封面.
  Worker? _noticesWorker;

  /// 已经发起预加载的封面地址.
  final _precached = <String>{};

  @override
  void initState() {
    super.initState();
    _restartTimer();
    if (Get.isRegistered<SiteNoticeService>()) {
      _noticesWorker = ever<List<SiteNotice>>(
        SiteNoticeService.instance.notices,
        (_) => _precacheCovers(),
      );
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _precacheCovers();
  }

  @override
  void dispose() {
    _noticesWorker?.dispose();
    _timer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  /// 提前把所有封面载入图片缓存, 切到下一篇时图片已经解码好, 不会先空白再出现.
  void _precacheCovers() {
    if (!mounted || !Get.isRegistered<SiteNoticeService>()) {
      return;
    }
    for (final notice in SiteNoticeService.instance.notices) {
      final url = notice.cover;
      if (url.isEmpty || !_precached.add(url)) {
        continue;
      }
      unawaited(
        precacheImage(
          CachedNetworkImageProvider(url),
          context,
          onError: (error, _) => Log.w('预加载通知封面失败: $url, $error'),
        ),
      );
    }
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
                    // 提前构建相邻页, 滑进来时内容已经就绪.
                    allowImplicitScrolling: true,
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
                  child: _PageCounter(
                    current: _page % notices.length + 1,
                    total: notices.length,
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

/// 通知卡片右侧的页码, 宽度按最宽的写法固定.
///
/// 页码文字宽度一变, 左边滑动区域就跟着变宽变窄, 正在进行的切换动画会被打乱,
/// 动画末尾出现跳动, 所以这里始终按 total/total 的宽度占位.
class _PageCounter extends StatelessWidget {
  const _PageCounter({required this.current, required this.total});

  final int current;
  final int total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Stack(
      alignment: Alignment.center,
      children: [
        // 只用来撑开宽度, 不显示.
        Visibility.maintain(
          visible: false,
          child: Text('$total/$total', style: style),
        ),
        Text('$current/$total', style: style),
      ],
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
                  // 封面已预先加载, 不做淡入, 免得每次滑到新页时闪一下.
                  fadeInDuration: Duration.zero,
                  fadeOutDuration: Duration.zero,
                  placeholder: (context, url) => placeholder,
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
