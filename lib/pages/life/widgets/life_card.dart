import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tucao/common/widgets/life_progress_bar.dart';
import 'package:tucao/common/widgets/loading_widget.dart';
import 'package:tucao/http/life_http.dart';
import 'package:tucao/models/life.dart';
import 'package:tucao/router/routes.dart';
import 'package:tucao/utils/logger.dart';

/// 续命卡片.
///
/// 站点靠广告收益维持, 官方把这笔收益折算成 "cc娘还能存活多少天",
/// 这里把会员中心的存活的进度条, 本人贡献与贡献者头像搬到我的页面,
/// 点按进入贡献榜. 未登录或取不到数据时整块不显示.
class LifeCard extends StatefulWidget {
  const LifeCard({super.key});

  @override
  State<LifeCard> createState() => _LifeCardState();
}

class _LifeCardState extends State<LifeCard> {
  LifeStatus? _status;
  bool _loading = true;
  String? _error;

  /// 拿不到数据时的线上诊断, 只在该分支显示.
  LifeDiagnosis? _diagnosis;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// 首屏由 [_loading] 的初值负责, 重试时才走 [_retry].
  Future<void> _retry() {
    setState(() {
      _loading = true;
      _error = null;
      _diagnosis = null;
    });
    return _load();
  }

  Future<void> _load() async {
    try {
      final status = await LifeHttp.fetchStatus();
      if (!mounted) {
        return;
      }
      setState(() {
        _status = status;
        _diagnosis = status == null ? LifeHttp.lastDiagnosis : null;
        _loading = false;
      });
    } catch (e, stackTrace) {
      Log.e('加载续命数据失败', error: e, stackTrace: stackTrace);
      if (!mounted) {
        return;
      }
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Card(
        child: SizedBox(height: 132, child: LoadingWidget()),
      );
    }
    final error = _error;
    if (error != null) {
      return Card(
        child: ListTile(
          leading: const Icon(Icons.error_outline),
          title: const Text('续命数据加载失败'),
          subtitle: Text(error, maxLines: 3, overflow: TextOverflow.ellipsis),
          trailing: const Icon(Icons.refresh),
          onTap: _retry,
        ),
      );
    }
    final status = _status;
    if (status == null) {
      // 站点没给续命区块. 原来的做法是整块隐藏, 但那样看不出是没登录
      // 还是站点改版, 这里把诊断写出来, 方便定位.
      return Card(
        child: ListTile(
          leading: const Icon(Icons.info_outline),
          title: const Text('暂时没有续命数据'),
          subtitle: Text(
            _diagnosis?.describe() ?? '站点没有返回续命区块',
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: const Icon(Icons.refresh),
          onTap: _retry,
        ),
      );
    }
    return _LifeCardBody(status: status);
  }
}

/// 续命卡片的内容.
class _LifeCardBody extends StatelessWidget {
  const _LifeCardBody({required this.status});

  final LifeStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final member = status.member;
    final chips = <String>[
      if (member.groupName.isNotEmpty) '会员组 ${member.groupName}',
      '积分 ${member.credit}',
      '居住 ${member.residentYears} 年',
    ];
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Get.toNamed(Routes.lifeRank),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.favorite, size: 15, color: scheme.primary),
                  const SizedBox(width: 6),
                  Text(
                    'cc娘, 还能存活',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    formatLifeDays(status.survivalDays),
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: scheme.primary,
                    ),
                  ),
                  Text(
                    ' 天',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // 站点按天数当百分数画, 100 天即整条.
              LifeProgressBar(ratio: status.survivalDays / 100),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '我已为ta续命 ${formatLifeDays(status.myDays)} 天',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                  if (status.contributors.isNotEmpty)
                    _ContributorAvatars(urls: status.contributors),
                  Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final text in chips) _Chip(text: text),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 贡献者头像, 重叠排在一起.
class _ContributorAvatars extends StatelessWidget {
  const _ContributorAvatars({required this.urls});

  final List<String> urls;

  /// 最多显示几个, 站点给的也是前几位.
  static const _max = 5;

  static const _size = 26.0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shown = urls.take(_max).toList();
    if (shown.isEmpty) {
      return const SizedBox.shrink();
    }
    // 头像互相压住 8 像素, 宽度按这个重叠量算.
    final step = _size - 8;
    return SizedBox(
      height: _size,
      width: _size + step * (shown.length - 1),
      child: Stack(
        children: [
          for (var i = 0; i < shown.length; i++)
            Positioned(
              left: step * (shown.length - 1 - i),
              child: Container(
                width: _size,
                height: _size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: scheme.surface, width: 2),
                ),
                child: ClipOval(
                  child: CachedNetworkImage(
                    imageUrl: shown[i],
                    fit: BoxFit.cover,
                    placeholder: (context, url) =>
                        ColoredBox(color: scheme.surfaceContainerHighest),
                    errorWidget: (context, url, error) => ColoredBox(
                      color: scheme.surfaceContainerHighest,
                      child: Icon(
                        Icons.person,
                        size: 14,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 卡片底部的小标签.
class _Chip extends StatelessWidget {
  const _Chip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
