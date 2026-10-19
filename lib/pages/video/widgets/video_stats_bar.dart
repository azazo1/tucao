import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tucao/common/widgets/stats_bar.dart';
import 'package:tucao/http/reply_http.dart';
import 'package:tucao/http/video_stats_http.dart';
import 'package:tucao/models/video.dart';
import 'package:tucao/models/video_stats.dart';
import 'package:tucao/services/site_favorite_service.dart';
import 'package:tucao/utils/logger.dart';

/// 播放页的统计条.
///
/// 与站点播放页顶部的图标一致: 播放 / 在线 / 评论 / 弹幕 / 追番.
/// 播放量, 评论数与追番数进入时各取一次, 在线人数每 30 秒刷新一次;
/// 应用退到后台时暂停刷新, 回到前台立即补一次.
/// 追番那一项可以点击: 站点把追番放在这个位置, 客户端跟着做,
/// 是否已经追番由站点账号的追番夹决定, 见 [SiteFavoriteService].
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
  bool _favoriteBusy = false;

  /// 站点追番与我的收藏页共用同一份缓存.
  late final SiteFavoriteService _favorites = SiteFavoriteService.instance;

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
    unawaited(_loadFavoriteState());
  }

  /// 追番状态整份缓存在 [SiteFavoriteService] 里, 拉到过就不再请求.
  ///
  /// 拉到之后由统计条外面的 Obx 跟着列表重建, 这里不额外触发.
  Future<void> _loadFavoriteState() async {
    if (_hid.isEmpty) {
      return;
    }
    await _favorites.ensureLoaded();
  }

  /// 点击追番: 没追番过就追番, 追过就取消.
  ///
  /// 站点数字不会立刻跟着变, 与官网一样先按本地结果加减一次.
  Future<void> _toggleFavorite() async {
    final video = widget.video;
    if (_favoriteBusy || video.hid.isEmpty) {
      return;
    }
    final service = _favorites;
    setState(() => _favoriteBusy = true);
    var action = '追番';
    try {
      // 还没拿到过列表时现拉一次: 失败后的冷却只该挡住后台轮询,
      // 不该把用户刚登录后的第一次点击也挡回去.
      if (!service.loaded) {
        await service.refresh(force: true);
      }
      if (!mounted) {
        return;
      }
      if (!service.loaded) {
        _showFavoriteTip(service.error.value ?? '登录后才能追番');
        return;
      }
      final existing = service.find(video.hid);
      if (existing == null) {
        await service.add(video);
      } else {
        action = '取消追番';
        await service.remove(existing);
      }
      if (!mounted) {
        return;
      }
      final count = _stats.favoriteCount;
      if (count == null) {
        unawaited(_loadCounts());
      } else {
        final next = count + (existing == null ? 1 : -1);
        _update(_stats.copyWith(favoriteCount: next < 0 ? 0 : next));
      }
      _showFavoriteTip(existing == null ? '已加入追番' : '已取消追番');
    } catch (e) {
      if (mounted) {
        _showFavoriteTip('$action失败: $e');
      }
      Log.d('$action失败: $e');
    } finally {
      if (mounted) {
        setState(() => _favoriteBusy = false);
      }
    }
  }

  void _showFavoriteTip(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
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
    // 追番状态来自站点服务, 用 Obx 跟着它刷新.
    return Obx(() {
      final favorited = _favorites.contains(video.hid);
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
            icon: favorited ? Icons.favorite : Icons.favorite_border,
            label: favorited ? '已追番, 点击取消' : '追番',
            value: stats.favoriteCount,
            // 提交中照旧保留可点外壳, 只换成转圈; 重复提交由 _toggleFavorite 挡.
            onTap: _toggleFavorite,
            busy: _favoriteBusy,
          ),
        ],
      );
    });
  }
}
