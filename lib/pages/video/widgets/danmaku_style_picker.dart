import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tucao/models/danmaku_send_style.dart';

/// 从底部弹出发送样式面板, 选择后直接写回 [style].
Future<void> showDanmakuStyleSheet(
  BuildContext context,
  Rx<DanmakuSendStyle> style,
) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Obx(
          () => DanmakuStylePicker(
            value: style.value,
            onChanged: (value) => style.value = value,
          ),
        ),
      ),
    ),
  );
}

/// 发送弹幕的样式选择: 上面选位置, 下面选颜色.
class DanmakuStylePicker extends StatelessWidget {
  const DanmakuStylePicker({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final DanmakuSendStyle value;
  final ValueChanged<DanmakuSendStyle> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SegmentedButton<DanmakuSendMode>(
          segments: [
            for (final mode in DanmakuSendMode.values)
              ButtonSegment(value: mode, label: Text(mode.label)),
          ],
          selected: {value.mode},
          showSelectedIcon: false,
          onSelectionChanged: (selection) =>
              onChanged(value.copyWith(mode: selection.first)),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final color in DanmakuSendStyle.colors)
              _ColorDot(
                color: color,
                selected: color == value.color,
                onTap: () => onChanged(value.copyWith(color: color)),
              ),
          ],
        ),
      ],
    );
  }
}

class _ColorDot extends StatelessWidget {
  const _ColorDot({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final int color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fill = Color(color | 0xFF000000);
    final hex = color.toRadixString(16).padLeft(6, '0').toUpperCase();
    return Semantics(
      button: true,
      selected: selected,
      label: '颜色 #$hex',
      child: InkResponse(
        onTap: onTap,
        radius: 20,
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: fill,
            shape: BoxShape.circle,
            // 白色在浅色背景上看不清, 未选中时也描一圈细边.
            border: Border.all(
              color: selected ? scheme.primary : scheme.outlineVariant,
              width: selected ? 3 : 1,
            ),
          ),
          child: selected
              ? Icon(
                  Icons.check,
                  size: 16,
                  color: fill.computeLuminance() > 0.5
                      ? Colors.black
                      : Colors.white,
                )
              : null,
        ),
      ),
    );
  }
}
