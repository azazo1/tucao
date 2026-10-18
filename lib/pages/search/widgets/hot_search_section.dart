import 'package:flutter/material.dart';
import 'package:tucao/common/style.dart';
import 'package:tucao/http/rank_http.dart';

/// 搜索页的热搜推荐区.
///
/// 搜索页只传入前十条, 这里按两列铺开, 其余从右侧的 "更多" 进入热搜榜.
class HotSearchSection extends StatelessWidget {
  const HotSearchSection({
    super.key,
    required this.items,
    required this.onKeyword,
    required this.onMore,
  });

  final List<HotKeyword> items;

  /// 点按某个关键词后交给搜索页发起搜索.
  final ValueChanged<String> onKeyword;

  /// 点按 "更多" 后进入完整的热搜榜.
  final VoidCallback onMore;

  /// 前三名的序号各用一种更醒目的颜色.
  static const rankColors = <Color>[
    Style.seedColor,
    Color(0xFFF57C00),
    Color(0xFFF9A825),
  ];

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: Style.pagePadding,
          child: Row(
            children: [
              const Text('热搜', style: TextStyle(fontSize: 13)),
              const Spacer(),
              TextButton(
                onPressed: onMore,
                style: TextButton.styleFrom(
                  minimumSize: Size.zero,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('更多'),
              ),
            ],
          ),
        ),
        Padding(
          padding: Style.pagePadding,
          child: Column(
            children: [
              for (var index = 0; index < items.length; index += 2)
                Row(
                  children: [
                    Expanded(
                      child: _HotKeywordTile(
                        item: items[index],
                        onTap: onKeyword,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: index + 1 < items.length
                          ? _HotKeywordTile(
                              item: items[index + 1],
                              onTap: onKeyword,
                            )
                          : const SizedBox.shrink(),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _HotKeywordTile extends StatelessWidget {
  const _HotKeywordTile({required this.item, required this.onTap});

  final HotKeyword item;

  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final rankColor =
        item.rank > 0 && item.rank <= HotSearchSection.rankColors.length
        ? HotSearchSection.rankColors[item.rank - 1]
        : scheme.onSurfaceVariant;
    final emphasized =
        item.rank > 0 && item.rank <= HotSearchSection.rankColors.length;
    return InkWell(
      onTap: () => onTap(item.keyword),
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            SizedBox(
              width: 24,
              child: Text(
                '${item.rank}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: emphasized ? FontWeight.w700 : FontWeight.w500,
                  color: rankColor,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                item.keyword,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: scheme.onSurface),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
