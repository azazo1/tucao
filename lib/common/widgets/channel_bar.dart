import 'package:flutter/material.dart';
import 'package:tucao/common/style.dart';

/// 分区列表项.
class ChannelItem {
  const ChannelItem({required this.id, required this.name});

  final int id;
  final String name;
}

/// 通用分区选择条.
///
/// 站点各页面都用同一套分区筛选, 这里统一成一个横向滚动的选择条.
class ChannelBar extends StatelessWidget {
  const ChannelBar({
    super.key,
    required this.channels,
    required this.currentId,
    required this.onChanged,
    this.showAll = false,
    this.allLabel = '全部',
  });

  final List<ChannelItem> channels;
  final int? currentId;
  final ValueChanged<int?> onChanged;

  /// 是否显示 "全部" 选项.
  final bool showAll;
  final String allLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final items = <ChannelItem>[
      if (showAll) ChannelItem(id: -1, name: allLabel),
      ...channels,
    ];
    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: items.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final item = items[index];
          final id = item.id == -1 ? null : item.id;
          final selected = currentId == id;
          return Center(
            child: ChoiceChip(
              label: Text(item.name),
              selected: selected,
              showCheckmark: false,
              labelStyle: TextStyle(
                fontSize: 13,
                color: selected ? scheme.onSecondaryContainer : null,
              ),
              onSelected: (_) => onChanged(id),
            ),
          );
        },
      ),
    );
  }
}

/// 排序方式.
class SortOption {
  const SortOption({required this.label, required this.value});

  final String label;

  /// 接口参数值, 为空表示站点默认排序.
  final String? value;
}

/// 排序选择条, 站点接口使用 `order` 参数.
class SortBar extends StatelessWidget {
  const SortBar({
    super.key,
    required this.options,
    required this.current,
    required this.onChanged,
  });

  final List<SortOption> options;
  final String? current;
  final ValueChanged<String?> onChanged;

  /// 站点列表接口支持的排序.
  static const videoSort = [
    SortOption(label: '最新', value: 'date'),
    SortOption(label: '弹幕', value: 'mukio'),
    SortOption(label: '播放', value: 'views'),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: Style.pagePadding,
      child: Row(
        children: [
          for (final option in options) ...[
            InkWell(
              onTap: () => onChanged(option.value),
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 4,
                ),
                child: Text(
                  option.label,
                  style: TextStyle(
                    fontSize: 13,
                    color: current == option.value
                        ? scheme.primary
                        : scheme.onSurfaceVariant,
                    fontWeight: current == option.value
                        ? FontWeight.w600
                        : FontWeight.normal,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
          ],
        ],
      ),
    );
  }
}
