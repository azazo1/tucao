import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:tucao/common/adaptive.dart';
import 'package:tucao/http/danmaku_http.dart';
import 'package:tucao/models/api_response.dart';
import 'package:tucao/models/danmaku.dart';
import 'package:tucao/models/download_task.dart';
import 'package:tucao/models/video.dart';
import 'package:tucao/pages/video/cast_flow.dart';
import 'package:tucao/pages/video/video_page.dart';
import 'package:tucao/pages/video/widgets/player_view.dart';
import 'package:tucao/pages/video/widgets/video_info.dart';
import 'package:tucao/plugin/player/player_brightness.dart';
import 'package:tucao/plugin/player/player_controller.dart';
import 'package:tucao/services/download/download_service.dart';
import 'package:tucao/services/history_service.dart';
import 'package:tucao/utils/logger.dart';
import 'package:tucao/utils/storage_pref.dart';
import 'package:tucao/utils/utils.dart';

/// 离线播放页: 复用主播放器, 视频信息与弹幕读本地缓存.
///
/// 只有已缓存的分P可播, 其余分P保留位置但没有地址, 序号与观看历史一致.
class OfflineVideoPage extends StatefulWidget {
  const OfflineVideoPage({super.key, required this.video, required this.part});

  final VideoModel video;
  final int part;

  /// 打开某个视频的离线播放. [part] 为空时接着上次看的已缓存分P.
  static Future<void> open(
    BuildContext context,
    String hid, {
    int? part,
  }) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final VideoModel? loaded;
    try {
      loaded = await DownloadService.instance.offlineVideo(hid);
    } catch (error, stackTrace) {
      Log.e('读取离线缓存失败 $hid', error: error, stackTrace: stackTrace);
      messenger?.showSnackBar(const SnackBar(content: Text('读取离线缓存失败')));
      return;
    }
    if (loaded == null || loaded.parts.every((item) => item.isThirdParty)) {
      messenger?.showSnackBar(
        const SnackBar(content: Text('本地文件缺失或不完整, 请重新下载')),
      );
      return;
    }
    final VideoModel video = loaded;
    bool playable(int? index) =>
        index != null &&
        index >= 0 &&
        index < video.parts.length &&
        !video.parts[index].isThirdParty;
    final last = Get.isRegistered<HistoryService>()
        ? HistoryService.instance.latestOf(hid)?.part
        : null;
    final target = playable(part)
        ? part!
        : playable(last)
        ? last!
        : video.parts.indexWhere((item) => !item.isThirdParty);
    Log.i('打开离线播放 $hid 分P ${target + 1}');
    // 不等待页面关闭, 调用方的忙碌状态只覆盖读取本地信息这一段.
    unawaited(Get.to(() => OfflineVideoPage(video: video, part: target)));
  }

  @override
  State<OfflineVideoPage> createState() => _OfflineVideoPageState();
}

class _OfflineVideoPageState extends State<OfflineVideoPage>
    with WidgetsBindingObserver {
  late final String _tag = 'offline_${identityHashCode(this)}';
  late final PlayerPageController _controller;
  final _service = DownloadService.instance;
  final _playerKey = GlobalKey();
  bool _fullscreen = false;

  /// 投屏流程, 与在线页共用; 本地文件由转发服务读给电视.
  late final CastFlow _castFlow;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final video = widget.video;
    _controller = Get.put(
      PlayerPageController(
        hid: video.hid,
        part: widget.part,
        initial: video,
        loadVideo: (_) async => ApiResponse(code: '200', result: video),
        loadDanmaku: _loadDanmaku,
        loadPlayPage: false,
        missingSourceMessage: '该分P未缓存, 可在线观看',
      ),
      tag: _tag,
    );
    _castFlow = CastFlow(controller: _controller, toast: _toast)
      ..addListener(_onCastChanged);
  }

  /// 投屏开始或收起时换掉播放区与顶栏按钮.
  void _onCastChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _toast(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  /// 优先读本地弹幕. 老缓存没有弹幕时联网补一次, 失败就不显示.
  Future<List<DanmakuModel>> _loadDanmaku(
    int typeId,
    String hid,
    int part,
  ) async {
    final saved = await _service.savedDanmaku('$hid-$part');
    if (saved != null) {
      return saved;
    }
    if (typeId <= 0) {
      return const [];
    }
    try {
      return await DanmakuHttp.fetch(typeId: typeId, hid: hid, part: part);
    } catch (error) {
      Log.w('离线播放联网补弹幕失败 $hid-$part: $error');
      return const [];
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _castFlow
      ..removeListener(_onCastChanged)
      ..dispose();
    _controller.detachDanmaku();
    if (Get.isRegistered<PlayerPageController>(tag: _tag)) {
      Get.delete<PlayerPageController>(tag: _tag);
    }
    if (_fullscreen) {
      _restoreOrientation();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && !Pref.playerBackground) {
      _controller.player.pause();
    }
  }

  Future<void> _enterFullscreen() async {
    setState(() => _fullscreen = true);
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  Future<void> _exitFullscreen() async {
    setState(() => _fullscreen = false);
    await _restoreOrientation();
  }

  Future<void> _restoreOrientation() async {
    await SystemChrome.setPreferredOrientations(const []);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  /// 转到在线播放页, 接着当前分P.
  Future<void> _openOnline() async {
    // 在线页另起投屏, 这里先让电视停下.
    await _castFlow.finish(restore: false);
    await _controller.player.pause();
    if (_fullscreen) {
      await _exitFullscreen();
    }
    if (!mounted) {
      return;
    }
    VideoPage.openByHid(widget.video.hid, part: _controller.part.value);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_fullscreen,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _fullscreen) {
          _exitFullscreen();
        }
      },
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        backgroundColor: _fullscreen
            ? Colors.black
            : Theme.of(context).colorScheme.surface,
        appBar: _fullscreen ? _emptyAppBar : _buildAppBar(),
        body: LayoutBuilder(
          builder: (context, constraints) {
            if (!_fullscreen && Adaptive.useSplitVideoLayout(context)) {
              return Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: ColoredBox(
                      color: Colors.black,
                      child: Center(
                        child: AspectRatio(
                          aspectRatio: 16 / 9,
                          child: _buildPlayer(),
                        ),
                      ),
                    ),
                  ),
                  const VerticalDivider(width: 0.5),
                  Expanded(flex: 2, child: _buildContent()),
                ],
              );
            }
            final inline = (constraints.maxWidth * 9 / 16).clamp(
              0.0,
              constraints.maxHeight / 2,
            );
            return Stack(
              children: [
                Positioned(
                  left: 0,
                  top: 0,
                  right: 0,
                  height: _fullscreen ? constraints.maxHeight : inline,
                  child: _buildPlayer(),
                ),
                Positioned(
                  left: 0,
                  top: inline,
                  right: 0,
                  bottom: 0,
                  child: Offstage(
                    offstage: _fullscreen,
                    child: TickerMode(
                      enabled: !_fullscreen,
                      child: _buildContent(),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  static final _emptyAppBar = PreferredSize(
    preferredSize: Size.zero,
    child: SizedBox.shrink(),
  );

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: Text(
        widget.video.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 15),
      ),
      actions: [
        CastButton(flow: _castFlow),
        IconButton(
          key: const ValueKey('offline-open-online'),
          tooltip: '在线观看',
          icon: const Icon(Icons.public),
          onPressed: () => unawaited(_openOnline()),
        ),
      ],
    );
  }

  Widget _buildPlayer() {
    // 固定 key, 进出全屏或切换分栏时搬动播放器, 不重新挂载.
    return KeyedSubtree(key: _playerKey, child: _buildPlayerView());
  }

  Widget _buildPlayerView() {
    return Obx(
      () => VideoPlayerView(
        controller: _controller,
        fullscreen: _fullscreen,
        cast: _castFlow.session,
        onExitCast: () => unawaited(_castFlow.finish(restore: true)),
        onToggleFullscreen: _fullscreen ? _exitFullscreen : _enterFullscreen,
        onOpenWebsite: () => unawaited(_openOnline()),
        websiteLabel: '在线观看',
        websiteIcon: Icons.public,
        // 离线页只看本地缓存, 发弹幕请到在线播放页.
        danmakuInput: false,
        brightness: const ScreenPlayerBrightness(),
        coverFile: _service.covers.contains(widget.video.hid)
            ? _service.coverFile(widget.video.hid)
            : null,
      ),
    );
  }

  Widget _buildContent() {
    final parts = widget.video.parts;
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: VideoInfoPanel(controller: _controller, onlineStats: false),
        ),
        const SliverToBoxAdapter(child: Divider(height: 1)),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              '分P (${parts.where((item) => !item.isThirdParty).length}/${parts.length} 已缓存)',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
        ),
        SliverList.builder(
          itemCount: parts.length,
          itemBuilder: (context, index) => _OfflinePartTile(
            key: ValueKey('offline-part-$index'),
            index: index,
            part: parts[index],
            controller: _controller,
            task: () => _service.find('${widget.video.hid}-$index'),
            onUnavailable: () => _showUnavailable(index),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }

  void _showUnavailable(int index) {
    final task = _service.find('${widget.video.hid}-$index');
    final downloading =
        task?.status == DownloadStatus.downloading ||
        task?.status == DownloadStatus.queued;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          downloading
              ? 'P${index + 1} 还在缓存中'
              : task?.status == DownloadStatus.completed
              ? 'P${index + 1} 刚缓存好, 重新进入本页即可播放'
              : 'P${index + 1} 未缓存',
        ),
        action: SnackBarAction(
          label: '在线观看',
          onPressed: () {
            unawaited(_controller.player.pause());
            VideoPage.openByHid(widget.video.hid, part: index);
          },
        ),
      ),
    );
  }
}

/// 离线页的分P行: 已缓存可点播放, 未缓存显示状态.
class _OfflinePartTile extends StatelessWidget {
  const _OfflinePartTile({
    super.key,
    required this.index,
    required this.part,
    required this.controller,
    required this.task,
    required this.onUnavailable,
  });

  final int index;
  final VideoPart part;
  final PlayerPageController controller;
  final DownloadTask? Function() task;
  final VoidCallback onUnavailable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final available = !part.isThirdParty;
    return Obx(() {
      final selected = controller.part.value == index;
      // 在 Obx 里遍历任务列表, 缓存进度变化时这一行跟着刷新.
      final current = task();
      final status = _status(current, available);
      final color = selected
          ? scheme.primary
          : available
          ? scheme.onSurface
          : scheme.onSurfaceVariant.withValues(alpha: 0.7);
      return ListTile(
        dense: true,
        selected: selected,
        leading: Container(
          width: 40,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? scheme.primaryContainer
                : scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            'P${index + 1}',
            style: theme.textTheme.labelMedium?.copyWith(
              color: selected ? scheme.onPrimaryContainer : color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        title: Text(
          part.title.isEmpty ? '第 ${index + 1} P' : part.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(color: color),
        ),
        subtitle: Text(
          status,
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        trailing: selected
            ? Icon(Icons.equalizer, color: scheme.primary)
            : available
            ? null
            : Icon(Icons.cloud_outlined, color: scheme.onSurfaceVariant),
        onTap: () {
          if (!available) {
            onUnavailable();
          } else if (!selected) {
            unawaited(controller.switchPart(index));
          }
        },
      );
    });
  }

  static String _status(DownloadTask? task, bool available) {
    if (available) {
      return task != null && task.received > 0
          ? '已缓存 ${Utils.formatBytes(task.received)}'
          : '已缓存';
    }
    switch (task?.status) {
      case DownloadStatus.downloading:
      case DownloadStatus.queued:
        final progress = task!.progress;
        return progress == null
            ? '缓存中'
            : '缓存中 ${(progress * 100).toStringAsFixed(0)}%';
      case DownloadStatus.paused:
        return '已暂停';
      case DownloadStatus.failed:
        return '缓存失败';
      case DownloadStatus.completed:
        return '已缓存, 重新进入后可播放';
      case null:
        return '未缓存';
    }
  }
}
