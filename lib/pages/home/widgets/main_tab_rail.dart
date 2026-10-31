import 'package:flutter/material.dart';

/// 首页主分区的左侧竖排切换条.
///
/// 横屏矮屏下顶上放不下一条横向标签, 把它竖到左边, 每个分区的几十个 dp
/// 就能还给内容区. 每项只显示分区名, 选中的用容器色打底.
class MainTabRail extends StatelessWidget {
  const MainTabRail({
    super.key,
    required this.labels,
    required this.index,
    required this.onSelected,
  });

  /// 竖排条占用的宽度.
  static const width = 84.0;

  final List<String> labels;

  /// 当前选中的分区下标.
  final int index;

  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: width,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        itemCount: labels.length,
        separatorBuilder: (context, i) => const SizedBox(height: 4),
        itemBuilder: (context, i) {
          final selected = i == index;
          return InkWell(
            onTap: () => onSelected(i),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
              decoration: BoxDecoration(
                color: selected ? scheme.secondaryContainer : null,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                labels[i],
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: selected
                      ? scheme.onSecondaryContainer
                      : scheme.onSurfaceVariant,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
