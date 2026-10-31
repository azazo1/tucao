import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tucao/common/style.dart';
import 'package:tucao/common/widgets/video_card.dart';
import 'package:tucao/pages/video/video_page.dart';
import 'package:tucao/services/history_service.dart';
import 'package:tucao/utils/logger.dart';

/// 首页顶部的继续观看卡片, 取最近几条没看完的记录.
///
/// 多条时做成可左右滑动的卡片, 两侧露出相邻卡片的边, 一条时只显示一张.
/// 太久以前的记录多半已经不打算接着看了, 只取 [maxAge] 以内的.
/// 关掉的那条本次启动内不再出现, 下次启动重新判断.
class ContinueWatchingBanner extends StatefulWidget {
  const ContinueWatchingBanner({super.key});

  static const maxAge = Duration(days: 7);

  /// 最多显示几条, 再多就该去历史页里找了.
  static const maxItems = 5;

  /// 进度太少的记录可能只是点进去看了一眼, 不算在看.
  static const minPercent = 0.02;

  /// 封面宽度, 卡片高度跟着封面比例走.
  static const coverWidth = 96.0;

  /// 本次启动内用户关掉过的视频.
  static final _dismissed = <String>{};

  /// 按规则从历史里挑出要提示的记录, 保持历史顺序, 最多 [maxItems] 条.
  static List<HistoryItem> pickAll(
    Iterable<HistoryItem> history,
    DateTime now,
  ) {
    final oldest = now.subtract(maxAge).millisecondsSinceEpoch;
    final picked = <HistoryItem>[];
    final seen = <String>{};
    for (final item in history) {
      // 历史按时间倒序, 第一条过期后后面的只会更旧.
      if (item.updateTime < oldest) break;
      final hid = item.video.hid;
      if (_dismissed.contains(hid) || !seen.add(hid)) continue;
      if (item.finished || item.percent < minPercent) continue;
      picked.add(item);
      if (picked.length >= maxItems) break;
    }
    return picked;
  }

  @override
  State<ContinueWatchingBanner> createState() => _ContinueWatchingBannerState();
}

class _ContinueWatchingBannerState extends State<ContinueWatchingBanner> {
  /// 每页占可视宽度的比例, 剩下的留给两侧露出的相邻卡片.
  final _pageController = PageController(viewportFraction: 0.9);

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _dismiss(HistoryItem item) {
    Log.i('关闭继续观看提示: ${item.video.title}');
    setState(() => ContinueWatchingBanner._dismissed.add(item.video.hid));
  }

  void _open(HistoryItem item) {
    Log.i('从首页继续观看 ${item.video.title} P${item.part + 1}');
    VideoPage.open(item.video, part: item.part);
  }

  @override
  Widget build(BuildContext context) {
    if (!Get.isRegistered<HistoryService>()) {
      return const SizedBox.shrink();
    }
    final history = HistoryService.instance;
    return Obx(() {
      final items = ContinueWatchingBanner.pickAll(
        history.list,
        DateTime.now(),
      );
      return AnimatedSize(
        duration: const Duration(milliseconds: 200),
        alignment: Alignment.topCenter,
        child: items.isEmpty
            ? const SizedBox(width: double.infinity)
            : _build(items),
      );
    });
  }

  Widget _build(List<HistoryItem> items) {
    const height = ContinueWatchingBanner.coverWidth / Style.coverAspectRatio;
    if (items.length == 1) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: SizedBox(height: height, child: _card(items.first, 0, 1)),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: SizedBox(
        height: height,
        child: PageView.builder(
          controller: _pageController,
          itemCount: items.length,
          itemBuilder: (context, index) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: _card(items[index], index, items.length),
          ),
        ),
      ),
    );
  }

  Widget _card(HistoryItem item, int index, int total) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final label = total > 1 ? '继续观看 ${index + 1}/$total' : '继续观看';
    return Material(
      color: scheme.secondaryContainer,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _open(item),
        child: Row(
          children: [
            SizedBox(
              width: ContinueWatchingBanner.coverWidth,
              child: VideoCover(url: item.video.cover, radius: 0),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSecondaryContainer,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.video.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSecondaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '看到 P${item.part + 1} ${(item.percent * 100).round()}%',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSecondaryContainer,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: '不再提示',
              onPressed: () => _dismiss(item),
              icon: Icon(
                Icons.close,
                size: 18,
                color: scheme.onSecondaryContainer,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
