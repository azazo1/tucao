import 'package:flutter/material.dart';
import 'package:tucao/models/video.dart';

/// 选集弹层: 列出全部分P, 点一下即切换.
///
/// 播放器控制条上的入口用它. 全屏时下方分P条在画面之外,
/// 只有这里能换集, 所以不依赖页面滚动位置.
Future<void> showPartPickerSheet(
  BuildContext context, {
  required List<VideoPart> parts,
  required int current,
  required ValueChanged<int> onSelected,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => _PartPickerSheet(
      parts: parts,
      current: current,
      onSelected: onSelected,
    ),
  );
}

/// 弹层正文: 一行标题加一列分P.
class _PartPickerSheet extends StatefulWidget {
  const _PartPickerSheet({
    required this.parts,
    required this.current,
    required this.onSelected,
  });

  final List<VideoPart> parts;
  final int current;
  final ValueChanged<int> onSelected;

  @override
  State<_PartPickerSheet> createState() => _PartPickerSheetState();
}

class _PartPickerSheetState extends State<_PartPickerSheet> {
  /// 每行固定高度, 既让长列表的滚动位置可算, 也让行高保持一致.
  static const _itemExtent = 56.0;

  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // 分P 多的时候当前项多半在屏幕之外, 打开后先把它滚进视野.
    WidgetsBinding.instance.addPostFrameCallback((_) => _revealCurrent());
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _revealCurrent() {
    if (!mounted || !_scrollController.hasClients) {
      return;
    }
    final position = _scrollController.position;
    if (!position.hasContentDimensions) {
      return;
    }
    // 当前项上方留一行, 免得它正好贴在顶边.
    final target = (widget.current - 1) * _itemExtent;
    _scrollController.jumpTo(target.clamp(0.0, position.maxScrollExtent));
  }

  /// 点到当前项时只关弹层, 不触发一次重新加载.
  void _select(int index) {
    if (index != widget.current) {
      widget.onSelected(index);
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: SizedBox(
        // 与缓存分P弹层取同一档高度, 长列表滚动, 横屏全屏下也够用.
        height: MediaQuery.sizeOf(context).height * 0.72,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text('选集', style: theme.textTheme.titleMedium),
                  const SizedBox(width: 8),
                  Text(
                    '共 ${widget.parts.length} 个分 P',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                itemExtent: _itemExtent,
                itemCount: widget.parts.length,
                itemBuilder: (context, index) => _PartRow(
                  index: index,
                  part: widget.parts[index],
                  selected: index == widget.current,
                  onTap: () => _select(index),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 单个分P: 左边序号, 中间标题, 右边状态.
class _PartRow extends StatelessWidget {
  const _PartRow({
    required this.index,
    required this.part,
    required this.selected,
    required this.onTap,
  });

  final int index;
  final VideoPart part;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final title = part.title.trim();
    // 第三方源已经不给播放地址, 与页面下方的分P条用同一种标记.
    final unavailable = part.isThirdParty;
    final labelColor = selected
        ? scheme.onPrimaryContainer
        : unavailable
        ? scheme.outline
        : scheme.onSurfaceVariant;
    return Material(
      color: selected
          ? scheme.primaryContainer.withValues(alpha: 0.9)
          : Colors.transparent,
      child: InkWell(
        key: ValueKey('part-picker-$index'),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              SizedBox(
                width: 36,
                child: Text(
                  'P${index + 1}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: labelColor,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  title.isEmpty ? '第 ${index + 1} 集' : title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    color: selected
                        ? scheme.onPrimaryContainer
                        : unavailable
                        ? scheme.outline
                        : scheme.onSurface,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    decoration: unavailable
                        ? TextDecoration.lineThrough
                        : TextDecoration.none,
                  ),
                ),
              ),
              if (unavailable) ...[
                const SizedBox(width: 8),
                Icon(Icons.link_off, size: 15, color: scheme.outline),
              ],
              if (selected) ...[
                const SizedBox(width: 8),
                Icon(Icons.check, size: 18, color: scheme.onPrimaryContainer),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
