import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tucao/common/style.dart';
import 'package:tucao/models/video.dart';
import 'package:tucao/plugin/player/player_controller.dart';
import 'package:tucao/router/routes.dart';
import 'package:tucao/utils/date_utils.dart';
import 'package:tucao/utils/utils.dart';

/// 播放页下方的视频信息区.
class VideoInfoPanel extends StatelessWidget {
  const VideoInfoPanel({super.key, required this.controller});

  final PlayerPageController controller;

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
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            video.title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 6),
          _buildMeta(context, video),
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
          if (video.description.isNotEmpty) ...[
            const SizedBox(height: 8),
            _Description(text: video.description),
          ],
        ],
      ),
    );
  }

  Widget _buildMeta(BuildContext context, VideoModel video) {
    final theme = Theme.of(context);
    final style = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Wrap(
      spacing: 10,
      runSpacing: 4,
      children: [
        _metaItem(
          Icons.play_circle_outline,
          Utils.formatCount(video.playCount),
          style,
        ),
        _metaItem(
          Icons.subtitles_outlined,
          '${Utils.formatCount(video.danmakuCount)} 弹幕',
          style,
        ),
        if (video.createTime > 0)
          _metaItem(Icons.schedule, DateUtil.relative(video.createTime), style),
        if (video.typeName.isNotEmpty)
          _metaItem(Icons.local_offer_outlined, video.typeName, style),
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
  const _Description({required this.text});

  final String text;

  @override
  State<_Description> createState() => _DescriptionState();
}

class _DescriptionState extends State<_Description> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.text,
          maxLines: _expanded ? null : 3,
          overflow: _expanded ? null : TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(height: 1.5),
        ),
        GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
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
  }
}

/// 分P列表, 多于一个分P时展示.
class VideoPartBar extends StatelessWidget {
  const VideoPartBar({super.key, required this.controller});

  final PlayerPageController controller;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final parts = controller.parts;
      if (parts.length <= 1) {
        return const SizedBox.shrink();
      }
      final current = controller.part.value;
      return SizedBox(
        height: 38,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: Style.pagePadding,
          itemCount: parts.length,
          separatorBuilder: (context, index) => const SizedBox(width: 6),
          itemBuilder: (context, index) => _PartChip(
            index: index,
            title: parts[index].title,
            selected: index == current,
            onTap: () => controller.switchPart(index),
          ),
        ),
      );
    });
  }
}

class _PartChip extends StatelessWidget {
  const _PartChip({
    required this.index,
    required this.title,
    required this.selected,
    required this.onTap,
  });

  final int index;
  final String title;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = title.isEmpty ? 'P${index + 1}' : 'P${index + 1} $title';
    return Center(
      child: Material(
        color: selected ? scheme.primaryContainer : scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: selected
                    ? scheme.onPrimaryContainer
                    : scheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
