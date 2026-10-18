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
  int? _count;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
    _timer = Timer.periodic(widget.interval, (_) => unawaited(_refresh()));
  }

  Future<void> _refresh() async {
    try {
      final count = await VideoStatsHttp.fetchSiteOnline();
      if (mounted && count != null) {
        setState(() => _count = count);
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
    final count = _count;
    if (count == null) {
      return const SizedBox.shrink();
    }
    final scheme = Theme.of(context).colorScheme;
    return Text(
      '在线 ${Utils.formatCount(count)}',
      style: TextStyle(fontSize: 11, color: scheme.outline),
    );
  }
}
