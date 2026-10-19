import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:tucao/common/widgets/life_progress_bar.dart';
import 'package:tucao/models/life.dart';

/// 贡献榜的一条记录.
///
/// 条目不可点: 站点没给用户 id, 见 [LifeRankItem] 上的 TOFIX(site).
class LifeRankTile extends StatelessWidget {
  const LifeRankTile({super.key, required this.item, this.maxRatio = 0});

  final LifeRankItem item;

  /// 榜首条目的占比, 站点给的百分比很小, 这里按榜首归一化成整条长度.
  final double maxRatio;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final highlight = item.rank <= 3;
    final ratio = maxRatio > 0 ? item.ratio / maxRatio : 0.0;
    return Padding(
      // 横向留白写在条目里, 与项目里其它列表页一致: 列表自身的
      // Adaptive.sidePadding 在手机上为 0, 靠条目内边距让内容不贴屏幕边缘.
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 26,
            child: Text(
              '${item.rank}',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: highlight ? scheme.primary : scheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 8),
          ClipOval(
            child: SizedBox(
              width: 40,
              height: 40,
              child: item.avatar.isEmpty
                  ? ColoredBox(
                      color: scheme.surfaceContainerHighest,
                      child: _placeholder(scheme),
                    )
                  : CachedNetworkImage(
                      imageUrl: item.avatar,
                      fit: BoxFit.cover,
                      placeholder: (context, url) =>
                          ColoredBox(color: scheme.surfaceContainerHighest),
                      errorWidget: (context, url, error) => ColoredBox(
                        color: scheme.surfaceContainerHighest,
                        child: _placeholder(scheme),
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.userName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${formatLifeDays(item.days)} 天',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: scheme.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                LifeProgressBar(ratio: ratio, height: 5),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _placeholder(ColorScheme scheme) =>
      Icon(Icons.person, size: 20, color: scheme.onSurfaceVariant);
}
