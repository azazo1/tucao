import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tucao/common/widgets/stats_bar.dart';
import 'package:tucao/http/reply_http.dart';
import 'package:tucao/http/video_stats_http.dart';
import 'package:tucao/models/video.dart';
import 'package:tucao/models/video_stats.dart';
import 'package:tucao/utils/logger.dart';

/// 播放页的统计条.
///
/// 与站点播放页顶部的图标一致: 播放 / 在线 / 评论 / 弹幕 / 追番.
/// 播放量, 评论数与追番数进入时各取一次, 在线人数每 30 秒刷新一次;
/// 应用退到后台时暂停刷新, 回到前台立即补一次.
class VideoStatsBar extends StatefulWidget {
  const VideoStatsBar({super.key, required this.video});

  final VideoModel video;

  @override
  State<VideoStatsBar> createState() => _VideoStatsBarState();
}

class _VideoStatsBarState extends State<VideoStatsBar>
    with WidgetsBindingObserver {
  /// 与站点播放页的轮询间隔一致.
  static const _onlineInterval = Duration(seconds: 30);

  VideoStats _stats = const VideoStats();
  Timer? _timer;
  String _hid = '';
  int _typeId = 0;
  bool _countsRequested = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sync(widget.video);
  }

  @override
  void didUpdateWidget(covariant VideoStatsBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.video.hid != widget.video.hid ||
        oldWidget.video.typeId != widget.video.typeId ||
        !_countsRequested) {
      _sync(widget.video);
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

  void _sync(VideoModel video) {
    if (video.hid.isEmpty || video.typeId <= 0) {
      return;
    }
    if (video.hid != _hid || video.typeId != _typeId) {
      _hid = video.hid;
      _typeId = video.typeId;
      _stats = const VideoStats();
      _countsRequested = false;
      _timer?.cancel();
      _timer = null;
    }
    if (!_countsRequested) {
      _countsRequested = true;
      unawaited(_loadCounts());
      unawaited(_loadCommentCount());
    }
    unawaited(_refreshOnline());
    _startTimer();
  }

  void _startTimer() {
    _timer ??= Timer.periodic(_onlineInterval, (_) {
      // 退到后台时不再轮询, 回来后由 lifecycle 回调补一次.
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        unawaited(_refreshOnline());
      }
    });
  }

  Future<void> _loadCounts() async {
    final hid = _hid;
    try {
      final counts = await VideoStatsHttp.fetchCounts(hid: hid);
      if (!mounted || hid != _hid) {
        return;
      }
      _update(
        _stats.copyWith(
          playCount: counts.playCount,
          favoriteCount: counts.favoriteCount,
        ),
      );
    } catch (e) {
      if (hid == _hid) {
        // 允许下一次详情更新时重试.
        _countsRequested = false;
      }
      Log.d('读取播放与追番统计失败: $e');
    }
  }

  Future<void> _loadCommentCount() async {
    final typeId = _typeId;
    final hid = _hid;
    try {
      final count = await ReplyHttp.count(typeId: typeId, hid: hid);
      if (!mounted || hid != _hid || typeId != _typeId) {
        return;
      }
      _update(_stats.copyWith(commentCount: count));
    } catch (e) {
      Log.d('读取评论数失败: $e');
    }
  }

  Future<void> _refreshOnline() async {
    final hid = _hid;
    if (!mounted || hid.isEmpty) {
      return;
    }
    try {
      final count = await VideoStatsHttp.fetchOnline(hid: hid);
      if (!mounted || hid != _hid || count == null) {
        return;
      }
      _update(_stats.copyWith(onlineCount: count));
    } catch (e) {
      Log.d('读取在线人数失败: $e');
    }
  }

  void _update(VideoStats stats) {
    if (!mounted) {
      return;
    }
    setState(() => _stats = stats);
  }

  @override
  Widget build(BuildContext context) {
    final video = widget.video;
    final stats = _stats;
    return StatsBar(
      items: [
        StatsBarItem(
          icon: Icons.play_circle_outline,
          label: '播放',
          // 详情接口的数字先显示, 统计接口拿到新值后覆盖.
          value: stats.playCount ?? video.playCount,
        ),
        StatsBarItem(
          icon: Icons.bar_chart,
          label: '在线',
          value: stats.onlineCount,
        ),
        StatsBarItem(
          icon: Icons.chat_bubble_outline,
          label: '评论',
          value: stats.commentCount,
        ),
        StatsBarItem(
          icon: Icons.subtitles_outlined,
          label: '弹幕',
          value: video.danmakuCount,
        ),
        StatsBarItem(
          icon: Icons.favorite_border,
          label: '追番',
          value: stats.favoriteCount,
        ),
      ],
    );
  }
}
