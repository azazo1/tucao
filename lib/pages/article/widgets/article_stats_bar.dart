import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tucao/common/widgets/stats_bar.dart';
import 'package:tucao/http/api_path.dart';
import 'package:tucao/http/reply_http.dart';
import 'package:tucao/http/video_stats_http.dart';
import 'package:tucao/utils/logger.dart';

/// 档案详情的数据统计.
///
/// 与站点档案页顶部的三个图标一致: 播放 / 在线 / 评论.
/// 播放量与评论数进入时各取一次, 在线人数每 30 秒刷新一次.
class ArticleStatsBar extends StatefulWidget {
  const ArticleStatsBar({
    super.key,
    required this.hid,
    required this.commentTypeId,
  });

  final String hid;

  /// 评论楼层里的分区 id, 为 0 时不取评论数.
  final int commentTypeId;

  @override
  State<ArticleStatsBar> createState() => _ArticleStatsBarState();
}

class _ArticleStatsBarState extends State<ArticleStatsBar>
    with WidgetsBindingObserver {
  static const _onlineInterval = Duration(seconds: 30);

  int? _playCount;
  int? _onlineCount;
  int? _commentCount;
  Timer? _timer;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void didUpdateWidget(covariant ArticleStatsBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.hid != widget.hid ||
        oldWidget.commentTypeId != widget.commentTypeId) {
      _timer?.cancel();
      _timer = null;
      _playCount = null;
      _onlineCount = null;
      _commentCount = null;
      _loaded = false;
      _load();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshOnline());
    }
  }

  void _load() {
    if (_loaded) {
      return;
    }
    _loaded = true;
    unawaited(_loadCounts());
    unawaited(_loadCommentCount());
    unawaited(_refreshOnline());
    _timer ??= Timer.periodic(_onlineInterval, (_) {
      // 退到后台时不再轮询, 回来后由 lifecycle 回调补一次.
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        unawaited(_refreshOnline());
      }
    });
  }

  Future<void> _loadCounts() async {
    final hid = widget.hid;
    try {
      final counts = await VideoStatsHttp.fetchCounts(
        hid: hid,
        modelId: ApiPath.articleModelId,
      );
      if (!mounted || hid != widget.hid) {
        return;
      }
      setState(() => _playCount = counts.playCount);
    } catch (e) {
      Log.d('读取档案播放统计失败: $e');
    }
  }

  Future<void> _loadCommentCount() async {
    final typeId = widget.commentTypeId;
    final hid = widget.hid;
    if (typeId <= 0) {
      return;
    }
    try {
      final count = await ReplyHttp.count(typeId: typeId, hid: hid);
      if (!mounted || hid != widget.hid || typeId != widget.commentTypeId) {
        return;
      }
      setState(() => _commentCount = count);
    } catch (e) {
      Log.d('读取档案评论数失败: $e');
    }
  }

  Future<void> _refreshOnline() async {
    final hid = widget.hid;
    try {
      final count = await VideoStatsHttp.fetchOnline(
        hid: hid,
        modelId: ApiPath.articleModelId,
      );
      if (!mounted || hid != widget.hid || count == null) {
        return;
      }
      setState(() => _onlineCount = count);
    } catch (e) {
      Log.d('读取档案在线人数失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return StatsBar(
      items: [
        StatsBarItem(
          icon: Icons.play_circle_outline,
          label: '播放',
          value: _playCount,
        ),
        StatsBarItem(
          icon: Icons.bar_chart,
          label: '在线',
          value: _onlineCount,
        ),
        StatsBarItem(
          icon: Icons.chat_bubble_outline,
          label: '评论',
          value: _commentCount,
        ),
      ],
    );
  }
}
