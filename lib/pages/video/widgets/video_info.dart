import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tucao/common/style.dart';
import 'package:tucao/common/widgets/copy_selection_area.dart';
import 'package:tucao/models/video.dart';
import 'package:tucao/models/video_subject.dart';
import 'package:tucao/pages/video/widgets/subject_info.dart';
import 'package:tucao/pages/video/widgets/video_stats_bar.dart';
import 'package:tucao/plugin/player/player_controller.dart';
import 'package:tucao/router/routes.dart';
import 'package:tucao/services/history_service.dart';
import 'package:tucao/utils/clipboard.dart';
import 'package:tucao/utils/date_utils.dart';
import 'package:tucao/utils/html_text.dart';

/// 播放页下方的视频信息区.
class VideoInfoPanel extends StatelessWidget {
  const VideoInfoPanel({
    super.key,
    required this.controller,
    this.onlineStats = true,
  });

  final PlayerPageController controller;

  /// 是否联网拉取播放数, 评论数与在线人数, 离线播放时关闭.
  final bool onlineStats;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final video = controller.video.value;
      if (video == null) {
        return const SizedBox.shrink();
      }
      return _buildContent(context, video);
    });
  }

  Widget _buildContent(BuildContext context, VideoModel video) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final subject = controller.subjectInfo.value;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onLongPress: () => copyText(context, video.title),
            child: Text(
              video.title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
            ),
          ),
          const SizedBox(height: 8),
          _buildMeta(context, video, subject),
          if (video.userName.isNotEmpty) ...[
            const SizedBox(height: 8),
            InkWell(
              onTap: video.userId > 0
                  ? () => Get.toNamed(
                      Routes.space,
                      parameters: {'uid': video.userId.toString()},
                    )
                  : null,
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 12,
                      backgroundColor: scheme.secondaryContainer,
                      child: Icon(
                        Icons.person_outline,
                        size: 14,
                        color: scheme.onSecondaryContainer,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(video.userName, style: theme.textTheme.bodySmall),
                    if (video.userId > 0) ...[
                      const SizedBox(width: 4),
                      Icon(
                        Icons.chevron_right,
                        size: 14,
                        color: scheme.onSurfaceVariant,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
          if (controller.fullDescription.value != null ||
              video.description.isNotEmpty) ...[
            const SizedBox(height: 8),
            _Description(
              key: ValueKey(video.hid),
              text: controller.fullDescription.value ?? video.description,
            ),
          ],
          // 统计放在简介下方, 紧挨着分 P 上方的分隔线.
          if (onlineStats && video.typeId > 0) ...[
            const SizedBox(height: 10),
            VideoStatsBar(video: video),
          ],
        ],
      ),
    );
  }

  Widget _buildMeta(
    BuildContext context,
    VideoModel video,
    VideoSubjectInfo? subject,
  ) {
    final theme = Theme.of(context);
    final style = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Wrap(
      spacing: 10,
      runSpacing: 4,
      children: [
        if (video.createTime > 0)
          _metaItem(Icons.schedule, DateUtil.relative(video.createTime), style),
        if (video.typeName.isNotEmpty)
          _metaItem(Icons.local_offer_outlined, video.typeName, style),
        if (subject != null && subject.isNotEmpty)
          SubjectInfoSummary(info: subject),
      ],
    );
  }

  Widget _metaItem(IconData icon, String text, TextStyle? style) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: style?.color),
        const SizedBox(width: 3),
        Text(text, style: style),
      ],
    );
  }
}

/// 可折叠的简介.
class _Description extends StatefulWidget {
  const _Description({super.key, required this.text});

  final String text;

  @override
  State<_Description> createState() => _DescriptionState();
}

class _DescriptionState extends State<_Description> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = decodeHtmlText(widget.text);
    final style = theme.textTheme.bodySmall?.copyWith(height: 1.5);
    return LayoutBuilder(
      builder: (context, constraints) {
        // 用同样的样式量一次, 只有真的超过 3 行才显示展开按钮.
        final painter = TextPainter(
          text: TextSpan(text: text, style: style),
          maxLines: 3,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout(maxWidth: constraints.maxWidth);
        final overflows = painter.didExceedMaxLines;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CopySelectionArea(
              text: text,
              child: Text(
                text,
                maxLines: _expanded ? null : 3,
                overflow: _expanded ? null : TextOverflow.ellipsis,
                style: style,
              ),
            ),
            if (overflows)
              // 点击范围铺满整行, 文字仍靠左显示.
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _expanded = !_expanded),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    _expanded ? '收起' : '展开',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// 分P列表, 多于一个分P时展示.
///
/// 当前分P变化时自动滚到可见处, 看过的分P带标记.
class VideoPartBar extends StatefulWidget {
  const VideoPartBar({super.key, required this.controller});

  final PlayerPageController controller;

  @override
  State<VideoPartBar> createState() => _VideoPartBarState();
}

class _VideoPartBarState extends State<VideoPartBar> {
  /// 每个分P的 key, 用来把当前分P滚到可见处.
  final _keys = <int, GlobalKey>{};
  int? _scrolledTo;

  GlobalKey _keyOf(int index) => _keys.putIfAbsent(index, GlobalKey.new);

  void _scrollToCurrent(int index) {
    if (_scrolledTo == index) return;
    _scrolledTo = index;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = _keyOf(index).currentContext;
      if (!mounted || context == null) return;
      Scrollable.ensureVisible(
        context,
        alignment: 0.5,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final history = Get.isRegistered<HistoryService>()
        ? HistoryService.instance
        : null;
    return Obx(() {
      final parts = controller.parts;
      if (parts.length <= 1) {
        return const SizedBox.shrink();
      }
      final current = controller.part.value;
      final watched = history?.partsOf(controller.hid) ?? const {};
      _scrollToCurrent(current);
      // 分P不多, 直接全部构建, 才能保证当前分P有 context 可以滚过去.
      return SizedBox(
        height: 38,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: Style.pagePadding,
          child: Row(
            children: [
              for (var index = 0; index < parts.length; index++) ...[
                if (index > 0) const SizedBox(width: 6),
                _PartChip(
                  key: _keyOf(index),
                  index: index,
                  title: parts[index].title,
                  selected: index == current,
                  // 第三方源已不再提供播放地址, 提前标出来, 避免用户点进去才发现.
                  unavailable: parts[index].isThirdParty,
                  record: watched[index],
                  onTap: () => controller.switchPart(index),
                ),
              ],
            ],
          ),
        ),
      );
    });
  }
}

class _PartChip extends StatelessWidget {
  const _PartChip({
    super.key,
    required this.index,
    required this.title,
    required this.selected,
    required this.onTap,
    this.unavailable = false,
    this.record,
  });

  final int index;
  final String title;
  final bool selected;

  /// 该分P没有可用的播放地址.
  final bool unavailable;

  /// 该分P的观看记录, 没看过为空.
  final HistoryItem? record;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = title.isEmpty ? 'P${index + 1}' : 'P${index + 1} $title';
    final record = this.record;
    final finished = record?.finished ?? false;
    // 看了一部分的分P在底边画一段进度, 看完的打勾.
    final partial = record != null && !finished && record.percent > 0;
    final textColor = selected
        ? scheme.onPrimaryContainer
        : unavailable
        ? scheme.outline
        : scheme.onSurfaceVariant;
    final content = InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (unavailable) ...[
              Icon(Icons.link_off, size: 12, color: textColor),
              const SizedBox(width: 4),
            ] else if (finished && !selected) ...[
              Icon(Icons.check, size: 12, color: textColor),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: textColor,
                decoration: unavailable
                    ? TextDecoration.lineThrough
                    : TextDecoration.none,
              ),
            ),
          ],
        ),
      ),
    );
    return Center(
      child: Material(
        color: selected ? scheme.primaryContainer : scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(6),
        clipBehavior: Clip.antiAlias,
        child: !partial
            ? content
            : Stack(
                children: [
                  content,
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: record.percent,
                        child: Container(height: 2, color: scheme.primary),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
