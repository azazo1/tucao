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
  SiteNoticeService.instance.markSeen(notice.hid);
  Get.toNamed(Routes.article, parameters: {'hid': notice.hid});
}

/// 时间表上方的单行通知条, 轮换没看过的站务文章.
///
/// 点标题打开文章, 关掉后当前文章都算看过, 有新文章才会再出现.
class SiteNoticeBar extends StatefulWidget {
  const SiteNoticeBar({super.key});

  static const interval = Duration(seconds: 5);

  @override
  State<SiteNoticeBar> createState() => _SiteNoticeBarState();
}

class _SiteNoticeBarState extends State<SiteNoticeBar> {
  Timer? _timer;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(SiteNoticeBar.interval, (_) {
      if (mounted) {
        setState(() => _index++);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _dismiss() {
    Log.i('关闭首页通知条');
    SiteNoticeService.instance.markAllSeen();
  }

  @override
  Widget build(BuildContext context) {
    if (!Get.isRegistered<SiteNoticeService>()) {
      return const SizedBox.shrink();
    }
    final service = SiteNoticeService.instance;
    return Obx(() {
      final unread = service.unread;
      return AnimatedSize(
        duration: const Duration(milliseconds: 200),
        alignment: Alignment.topCenter,
        child: unread.isEmpty
            ? const SizedBox(width: double.infinity)
            : _build(unread, _index % unread.length),
      );
    });
  }

  Widget _build(List<SiteNotice> unread, int index) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final notice = unread[index];
    final reduced = MediaQuery.disableAnimationsOf(context);
    final textStyle = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurface,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 4, 0),
      child: SizedBox(
        height: 36,
        child: Row(
          children: [
            Icon(Icons.campaign_outlined, size: 18, color: scheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: InkWell(
                onTap: () => _openNotice(notice),
                borderRadius: BorderRadius.circular(6),
                child: AnimatedSwitcher(
                  duration: reduced
                      ? Duration.zero
                      : const Duration(milliseconds: 300),
                  layoutBuilder: (current, previous) => Stack(
                    alignment: Alignment.centerLeft,
                    children: [...previous, ?current],
                  ),
                  child: Text(
                    notice.title,
                    key: ValueKey(notice.hid),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textStyle,
                  ),
                ),
              ),
            ),
            if (unread.length > 1)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Text(
                  '${index + 1}/${unread.length}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            IconButton(
              onPressed: _dismiss,
              tooltip: '关闭通知',
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.close, size: 16, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

/// 顶栏的铃铛, 有没看过的站务文章时带红点数字, 点开列出全部.
class SiteNoticeBell extends StatelessWidget {
  const SiteNoticeBell({super.key});

  @override
  Widget build(BuildContext context) {
    if (!Get.isRegistered<SiteNoticeService>()) {
      return const SizedBox.shrink();
    }
    final service = SiteNoticeService.instance;
    return Obx(() {
      if (service.notices.isEmpty) {
        return const SizedBox.shrink();
      }
      final count = service.unread.length;
      return IconButton(
        tooltip: '站务公告',
        onPressed: () => _showSheet(context),
        icon: Badge(
          isLabelVisible: count > 0,
          label: Text('$count'),
          child: const Icon(Icons.notifications_none),
        ),
      );
    });
  }

  void _showSheet(BuildContext context) {
    final service = SiteNoticeService.instance;
    // 先记下哪些没看过, 面板里标出来, 再统一记为已读.
    final unread = {for (final item in service.unread) item.hid};
    service.markAllSeen();
    Log.i('打开站务公告列表, 未读 ${unread.length} 条');
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        builder: (context, controller) => Obx(
          () => ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '站务公告',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              for (final notice in service.notices)
                _NoticeTile(
                  notice: notice,
                  unread: unread.contains(notice.hid),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoticeTile extends StatelessWidget {
  const _NoticeTile({required this.notice, required this.unread});

  final SiteNotice notice;
  final bool unread;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return InkWell(
      onTap: () {
        Navigator.of(context).pop();
        _openNotice(notice);
      },
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                width: 56,
                height: 72,
                child: notice.cover.isEmpty
                    ? ColoredBox(color: scheme.surfaceContainerHighest)
                    : CachedNetworkImage(
                        imageUrl: notice.cover,
                        fit: BoxFit.cover,
                        errorWidget: (context, url, error) =>
                            ColoredBox(color: scheme.surfaceContainerHighest),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          notice.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (unread)
                        Padding(
                          padding: const EdgeInsets.only(left: 6, top: 6),
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: scheme.error,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (notice.summary.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      notice.summary,
                      maxLines: 2,
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
        ),
      ),
    );
  }
}
