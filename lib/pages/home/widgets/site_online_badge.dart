import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tucao/http/video_stats_http.dart';
import 'package:tucao/utils/logger.dart';
import 'package:tucao/utils/utils.dart';

/// 首页标题旁的站内实时在线人数.
///
/// 数据来自站点 ol.php 的 olAll 字段, 按固定间隔重新拉取.
class SiteOnlineBadge extends StatefulWidget {
  const SiteOnlineBadge({
    super.key,
    this.interval = const Duration(seconds: 30),
  });

  final Duration interval;

  @override
  State<SiteOnlineBadge> createState() => _SiteOnlineBadgeState();
}

class _SiteOnlineBadgeState extends State<SiteOnlineBadge> {
  Timer? _timer;
  int? _online;
  int? _players;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
    _timer = Timer.periodic(widget.interval, (_) => unawaited(_refresh()));
  }

  Future<void> _refresh() async {
    try {
      final stats = await VideoStatsHttp.fetchSiteOnline();
      if (mounted) {
        setState(() {
          _online = stats.online ?? _online;
          _players = stats.players ?? _players;
        });
      }
    } catch (e) {
      Log.d('读取总站在线人数失败: $e');
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_online == null && _players == null) {
      return const SizedBox.shrink();
    }
    final scheme = Theme.of(context).colorScheme;
    final parts = <String>[
      if (_online != null) '在线 ${Utils.formatCount(_online!)}',
      if (_players != null) '播放器 ${Utils.formatCount(_players!)}',
    ];
    return Text(
      parts.join(' · '),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: 11, color: scheme.outline),
    );
  }
}
