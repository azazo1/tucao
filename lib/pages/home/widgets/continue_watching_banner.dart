import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tucao/common/widgets/video_card.dart';
import 'package:tucao/pages/video/video_page.dart';
import 'package:tucao/services/history_service.dart';
import 'package:tucao/utils/logger.dart';

/// 首页顶部的继续观看条, 取最近一条没看完的记录.
///
/// 太久以前的记录多半已经不打算接着看了, 只取 [maxAge] 以内的.
/// 关掉之后本次启动内不再出现, 下次启动重新判断.
class ContinueWatchingBanner extends StatefulWidget {
  const ContinueWatchingBanner({super.key});

  static const maxAge = Duration(days: 7);

  /// 进度太少的记录可能只是点进去看了一眼, 不算在看.
  static const minPercent = 0.02;

  /// 本次启动内用户关掉过的视频.
  static final _dismissed = <String>{};

  /// 按规则从历史里挑出要提示的那条, 没有合适的返回 null.
  static HistoryItem? pick(Iterable<HistoryItem> history, DateTime now) {
    final oldest = now.subtract(maxAge).millisecondsSinceEpoch;
    for (final item in history) {
      // 历史按时间倒序, 第一条过期后后面的只会更旧.
      if (item.updateTime < oldest) return null;
      if (_dismissed.contains(item.video.hid)) continue;
      if (item.finished || item.percent < minPercent) continue;
      return item;
    }
    return null;
  }

  @override
  State<ContinueWatchingBanner> createState() => _ContinueWatchingBannerState();
}

class _ContinueWatchingBannerState extends State<ContinueWatchingBanner> {
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
      final item = ContinueWatchingBanner.pick(history.list, DateTime.now());
      return AnimatedSize(
        duration: const Duration(milliseconds: 200),
        alignment: Alignment.topCenter,
        child: item == null
            ? const SizedBox(width: double.infinity)
            : _build(item),
      );
    });
  }

  Widget _build(HistoryItem item) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final partText = item.video.partCount > 1 ? 'P${item.part + 1} · ' : '';
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Material(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _open(item),
          child: Row(
            children: [
              SizedBox(
                width: 96,
                child: VideoCover(
                  url: item.video.cover,
                  radius: 0,
                  bottom: SizedBox(
                    height: 3,
                    child: LinearProgressIndicator(
                      value: item.percent,
                      minHeight: 3,
                      color: scheme.primary,
                      backgroundColor: Colors.black38,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '继续观看',
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
                      '$partText看到 ${(item.percent * 100).round()}%',
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
      ),
    );
  }
}
