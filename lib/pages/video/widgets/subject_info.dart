import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:tucao/models/video_subject.dart';

/// 番组信息摘要.
///
/// 只排进标题下方原有的元信息行, 不额外占一行; 点按后从底部弹层查看
/// 全部字段, 适合字段较多而横向空间有限的手机竖屏.
class SubjectInfoSummary extends StatelessWidget {
  const SubjectInfoSummary({super.key, required this.info});

  final VideoSubjectInfo info;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return InkWell(
      onTap: () => showSubjectInfoSheet(context, info),
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.movie_outlined, size: 13, color: style?.color),
            const SizedBox(width: 3),
            Flexible(
              child: Text(
                _summaryText(info),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style,
              ),
            ),
            Icon(Icons.chevron_right, size: 14, color: style?.color),
          ],
        ),
      ),
    );
  }

  /// 摘要优先取年代与首播, 不容易与分区名称重复.
  String _summaryText(VideoSubjectInfo info) {
    final parts = <String>[];
    final season = info.valueOf('年代');
    final premiere = info.valueOf('首播');
    final update = info.valueOf('更新');
    if (season.isNotEmpty) {
      parts.add(season);
    }
    if (premiere.isNotEmpty) {
      parts.add('$premiere 首播');
    } else if (update.isNotEmpty) {
      parts.add('$update 更新');
    }
    if (parts.isNotEmpty) {
      return parts.join(' · ');
    }
    return info.fields
        .take(2)
        .map((field) => '${field.label} ${field.value}')
        .join(' · ');
  }
}

/// 从底部弹层查看全部番组信息, 供摘要点按使用.
Future<void> showSubjectInfoSheet(BuildContext context, VideoSubjectInfo info) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      builder: (context, scrollController) => SafeArea(
        child: ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Text('番组信息', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            _SubjectInfoBody(info: info),
          ],
        ),
      ),
    ),
  );
}

/// 弹层正文: 左侧番组封面, 右侧字段表.
///
/// 排布跟站点播放页一致, 封面只占一列宽度, 排在字段左边;
/// 没有封面时字段独占整行, 与不加封面时的排版相同.
class _SubjectInfoBody extends StatelessWidget {
  const _SubjectInfoBody({required this.info});

  final VideoSubjectInfo info;

  /// 站点番组封面按 320 x 428 出图, 显示时保持这个比例.
  static const coverAspectRatio = 320 / 428;

  /// 封面显示宽度, 与站点播放页里约两成的占宽接近.
  static const coverWidth = 96.0;

  @override
  Widget build(BuildContext context) {
    final fields = [
      for (final field in info.fields) _SubjectFieldRow(field: field),
    ];
    if (!info.hasCover) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: fields,
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: coverWidth,
          child: _SubjectCover(url: info.cover),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: fields,
          ),
        ),
      ],
    );
  }
}

/// 番组封面.
///
/// 站点给的地址失效时退回占位色块, 不挡后面的字段.
class _SubjectCover extends StatelessWidget {
  const _SubjectCover({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: AspectRatio(
        aspectRatio: _SubjectInfoBody.coverAspectRatio,
        child: CachedNetworkImage(
          imageUrl: url,
          fit: BoxFit.cover,
          fadeInDuration: const Duration(milliseconds: 150),
          placeholder: (context, url) =>
              ColoredBox(color: scheme.surfaceContainerHighest),
          errorWidget: (context, url, error) => ColoredBox(
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
}

class _SubjectFieldRow extends StatelessWidget {
  const _SubjectFieldRow({required this.field});

  final SubjectField field;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 64,
            child: Text(
              field.label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              field.value,
              style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
