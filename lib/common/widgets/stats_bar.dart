import 'package:flutter/material.dart';
import 'package:tucao/utils/utils.dart';

/// 统计条里的一项.
class StatsBarItem {
  const StatsBarItem({
    required this.icon,
    required this.label,
    this.value,
    this.onTap,
    this.busy = false,
  });

  final IconData icon;

  /// 用于提示与无障碍描述.
  final String label;

  /// 为空表示还在加载.
  final int? value;

  /// 不为空时该项可以点击, 目前只有播放页的追番.
  ///
  /// 提交中不要把它置空: 可点与不可点的外壳不一样高, 统计条会跟着抖一下,
  /// 重复提交由 [onTap] 自己拦住.
  final VoidCallback? onTap;

  /// 提交中, 用同尺寸的转圈顶替图标, 高度不变.
  final bool busy;
}

/// 播放页与档案页共用的统计条.
///
/// 图标在上数字在下, 每项之间用细分隔线分开, 与站点播放页一致.
class StatsBar extends StatelessWidget {
  const StatsBar({super.key, required this.items});

  final List<StatsBarItem> items;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: '数据统计',
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0)
              Container(width: 0.5, height: 28, color: scheme.outlineVariant),
            Expanded(child: _StatsCell(item: items[i])),
          ],
        ],
      ),
    );
  }
}

class _StatsCell extends StatelessWidget {
  const _StatsCell({required this.item});

  final StatsBarItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final value = item.value;
    // 转圈与图标同样占 18 见方, 提交中换过去不会把统计条顶高.
    final icon = item.busy
        ? const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Icon(item.icon, size: 18, color: scheme.onSurfaceVariant);
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        icon,
        const SizedBox(height: 2),
        Text(
          value == null ? '…' : Utils.formatCount(value),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: scheme.onSurface,
          ),
        ),
      ],
    );
    final onTap = item.onTap;
    if (onTap == null) {
      return Tooltip(message: item.label, child: content);
    }
    // 可点击的项留出一点上下留白, 手指好按, 不影响只读的统计条.
    return Tooltip(
      message: item.label,
      child: Semantics(
        button: true,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: content,
          ),
        ),
      ),
    );
  }
}
