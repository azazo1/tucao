import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:tucao/common/widgets/loading_widget.dart';
import 'package:tucao/models/video.dart';
import 'package:tucao/pages/video/widgets/video_content_tabs.dart';
import 'package:tucao/pages/video/widgets/player_view.dart';
import 'package:tucao/pages/video/widgets/video_action.dart';
import 'package:tucao/pages/video/widgets/video_info.dart';
import 'package:tucao/pages/video/widgets/video_link_menu.dart';
import 'package:tucao/pages/video/widgets/download_sheet.dart';
import 'package:tucao/plugin/player/player_controller.dart';
import 'package:tucao/router/routes.dart';
import 'package:tucao/services/pip_service.dart';
import 'package:tucao/utils/logger.dart';
import 'package:tucao/utils/site_links.dart';
import 'package:tucao/utils/storage_pref.dart';
import 'package:url_launcher/url_launcher.dart';

/// 视频播放页.
///
/// 路由参数 `hid` 与可选的 `part` (分P序号, 从 0 开始).
class VideoPage extends StatefulWidget {
  const VideoPage({super.key});

  /// 从列表页进入, 带上已有的视频信息可以少一次白屏.
  static void open(VideoModel video, {int part = 0}) {
    Get.toNamed(
      Routes.video,
      parameters: {'hid': video.hid, 'part': part.toString()},
      arguments: video,
    );
  }

  /// 只有 hid 时进入.
  static void openByHid(String hid, {int part = 0}) {
    Get.toNamed(
      Routes.video,
      parameters: {'hid': hid, 'part': part.toString()},
    );
  }

  @override
  State<VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends State<VideoPage>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  late final TabController _contentTabs = TabController(length: 2, vsync: this);

  /// 同一视频可能被重复打开, 用实例标识区分控制器.
  late final String _tag = 'video_${identityHashCode(this)}';

  late final PlayerPageController _controller;

  /// 是否处于横屏全屏.
  bool _fullscreen = false;

  /// 设备是否支持画中画, 支持时播放器才显示入口.
  bool _pipSupported = false;

  /// 是否已经进入画中画小窗.
  bool _pipMode = false;

  /// 播放器区域的位置, 进入小窗时作为动画起点.
  final _playerKey = GlobalKey();

  /// 上一次同步给系统的自动进入条件, 避免每个进度回调都过一次通道.
  (bool, int, int)? _autoEnterState;

  bool _openingWebsite = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final parameters = Get.parameters;
    final hid = parameters['hid'] ?? '';
    final part = int.tryParse(parameters['part'] ?? '') ?? 0;
    final argument = Get.arguments;
    _controller = Get.put(
      PlayerPageController(
        hid: hid,
        part: part,
        // 列表页带了数据时先用着, 详情返回后再覆盖.
        initial: argument is VideoModel ? argument : null,
      ),
      tag: _tag,
    );
    _controller.player.addListener(_syncPipAutoEnter);
    PipService.instance.inPipMode.addListener(_onPipModeChanged);
    unawaited(_loadPipSupport());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.player.removeListener(_syncPipAutoEnter);
    PipService.instance.inPipMode.removeListener(_onPipModeChanged);
    // 离开播放页后不再自动进入小窗.
    unawaited(PipService.instance.setAutoEnter(enabled: false));
    _contentTabs.dispose();
    _controller.detachDanmaku();
    if (Get.isRegistered<PlayerPageController>(tag: _tag)) {
      Get.delete<PlayerPageController>(tag: _tag);
    }
    if (_fullscreen) {
      _restorePortrait();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 允许后台播放时, 切到后台不做处理.
    if (state == AppLifecycleState.paused && !Pref.playerBackground) {
      _controller.player.pause();
    }
  }

  /// 查询画中画支持情况, 支持时才接入自动进入.
  Future<void> _loadPipSupport() async {
    final supported = await PipService.instance.isSupported();
    if (!mounted || !supported) {
      return;
    }
    setState(() => _pipSupported = true);
    _syncPipAutoEnter();
  }

  /// 小窗状态变化: 切换页面布局, 并重新判断自动进入的条件.
  void _onPipModeChanged() {
    final inPip = PipService.instance.inPipMode.value;
    if (!mounted || inPip == _pipMode) {
      return;
    }
    setState(() => _pipMode = inPip);
    _syncPipAutoEnter();
  }

  /// 把自动进入小窗的条件交给系统.
  ///
  /// 只有开关打开, 正在播放, 且播放页就在最前面时才自动进入, 条件没变就不走通道.
  /// 暂停播放或已经在页面之上压了别的页面都会关掉它: 小窗显示的是当前界面,
  /// 上层还压着一个页面时进小窗会露出那个页面.
  void _syncPipAutoEnter() {
    if (!_pipSupported || !mounted) {
      return;
    }
    final player = _controller.player;
    final onTop = ModalRoute.of(context)?.isCurrent ?? false;
    final enabled = Pref.playerPipAuto && player.playing && !_pipMode && onTop;
    final width = player.videoWidth ?? 0;
    final height = player.videoHeight ?? 0;
    final state = (enabled, width, height);
    if (state == _autoEnterState) {
      return;
    }
    _autoEnterState = state;
    unawaited(
      PipService.instance.setAutoEnter(
        enabled: enabled,
        width: width,
        height: height,
      ),
    );
  }

  /// 进入小窗: 宽高比取当前画面, 动画起点取播放器区域.
  Future<void> _enterPip() async {
    if (!_pipSupported || _pipMode) {
      return;
    }
    final player = _controller.player;
    final entered = await PipService.instance.enter(
      width: player.videoWidth,
      height: player.videoHeight,
      sourceRect: _playerRectInPixels(),
    );
    if (entered) {
      Log.i('进入画中画');
      return;
    }
    if (mounted && (ModalRoute.of(context)?.isCurrent ?? false)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('当前设备无法进入画中画')));
    }
  }

  /// 播放器区域在屏幕上的位置, 单位是设备像素.
  Rect? _playerRectInPixels() {
    final box = _playerKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) {
      return null;
    }
    final ratio = MediaQuery.devicePixelRatioOf(context);
    final offset = box.localToGlobal(Offset.zero);
    return Rect.fromLTWH(
      offset.dx * ratio,
      offset.dy * ratio,
      box.size.width * ratio,
      box.size.height * ratio,
    );
  }

  /// 进入全屏: 横屏并隐藏系统栏.
  Future<void> _enterFullscreen() async {
    setState(() => _fullscreen = true);
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  /// 退出全屏: 恢复竖屏与系统栏.
  Future<void> _exitFullscreen() async {
    setState(() => _fullscreen = false);
    await _restorePortrait();
  }

  Future<void> _restorePortrait() async {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  @override
  Widget build(BuildContext context) {
    // 全屏与画中画都只留播放器, 两者共用同一套布局切换.
    final playerFill = _fullscreen || _pipMode;
    return PopScope(
      canPop: !_fullscreen,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _fullscreen) {
          _exitFullscreen();
        }
      },
      child: Scaffold(
        // 输入弹层自行避让键盘, 不压缩播放器和下方分页的高度.
        resizeToAvoidBottomInset: false,
        backgroundColor: playerFill
            ? Colors.black
            : Theme.of(context).colorScheme.surface,
        // 全屏时用零高度的占位替代标题栏, 保持 body 的 element 不被重建,
        // 否则切换全屏会重新挂载播放器与弹幕层.
        appBar: playerFill ? _emptyAppBar : _buildAppBar(),
        body: LayoutBuilder(
          builder: (context, constraints) {
            // 高度有限时为下方内容留下空间, 全屏仍铺满播放器.
            final inlinePlayerHeight = (constraints.maxWidth * 9 / 16).clamp(
              0.0,
              constraints.maxHeight / 2,
            );
            final playerHeight = playerFill
                ? constraints.maxHeight
                : inlinePlayerHeight;
            return Stack(
              children: [
                Positioned(
                  left: 0,
                  top: 0,
                  right: 0,
                  height: playerHeight,
                  child: _buildPlayerView(),
                ),
                Positioned(
                  left: 0,
                  top: inlinePlayerHeight,
                  right: 0,
                  bottom: 0,
                  child: Offstage(
                    offstage: playerFill,
                    child: TickerMode(
                      enabled: !playerFill,
                      child: _buildContentArea(),
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
      actions: [
        Obx(
          () => VideoLinkMenu(
            hid: _controller.hid,
            part: _controller.part.value,
            onOpenWebsite: _openWebsite,
            onDownload: _controller.video.value == null
                ? null
                : _openDownloadSheet,
          ),
        ),
      ],
      title: Obx(
        () => Text(
          _controller.video.value?.title ?? '视频',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 15),
        ),
      ),
    );
  }

  Widget _buildPlayerView() {
    return VideoPlayerView(
      key: _playerKey,
      controller: _controller,
      fullscreen: _fullscreen,
      pipMode: _pipMode,
      // 不支持时不给回调, 播放器就不显示入口.
      onEnterPip: _pipSupported ? _enterPip : null,
      onToggleFullscreen: _fullscreen ? _exitFullscreen : _enterFullscreen,
      onOpenWebsite: _openWebsite,
    );
  }

  Widget _buildContentArea() {
    return Obx(() {
      final error = _controller.error.value;
      if (error != null && _controller.video.value == null) {
        return ErrorWidgetView(message: error, onRetry: _controller.load);
      }
      return _buildContent();
    });
  }

  Widget _buildContent() {
    final video = _controller.video.value;
    if (video == null) {
      return _controller.firstLoading.value
          ? const LoadingWidget()
          : const EmptyWidget(message: '视频信息加载失败');
    }
    return VideoContentTabs(
      controller: _contentTabs,
      typeId: video.typeId,
      hid: _controller.hid,
      part: _controller.part.value,
      introduction: ListView(
        padding: EdgeInsets.zero,
        children: [
          VideoInfoPanel(controller: _controller),
          const Divider(),
          VideoPartBar(controller: _controller),
          VideoActionBar(
            controller: _controller,
            onComment: () => _contentTabs.animateTo(1),
          ),
        ],
      ),
    );
  }

  void _openDownloadSheet() {
    final video = _controller.video.value;
    if (video != null) {
      showVideoDownloadSheet(
        context,
        video: video,
        initialPart: _controller.part.value,
      );
    }
  }

  Future<void> _openWebsite() async {
    if (_openingWebsite) {
      return;
    }
    final uri = SiteLinks.video(_controller.hid, part: _controller.part.value);
    if (uri == null) {
      return;
    }
    _openingWebsite = true;
    try {
      // 即使用户允许后台播放, 外部浏览器打开前也暂停, 避免两个播放器同时出声.
      await _controller.player.pause();
      // 暂停触发的画中画同步可能晚于跳转, 这里直接关一次, 免得切到浏览器时进了小窗.
      await PipService.instance.setAutoEnter(enabled: false);
      if (!mounted || !(ModalRoute.of(context)?.isCurrent ?? false)) {
        return;
      }
      if (_fullscreen) {
        await _exitFullscreen();
      }
      if (!mounted || !(ModalRoute.of(context)?.isCurrent ?? false)) {
        return;
      }
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened && mounted && (ModalRoute.of(context)?.isCurrent ?? false)) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('无法打开浏览器, 可在菜单中复制链接')));
      }
    } catch (error, stackTrace) {
      Log.e('打开视频站点页面失败', error: error, stackTrace: stackTrace);
      if (mounted && (ModalRoute.of(context)?.isCurrent ?? false)) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('浏览器打开失败, 可在菜单中复制链接')));
      }
    } finally {
      _openingWebsite = false;
    }
  }
}
