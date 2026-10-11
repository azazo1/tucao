import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:tucao/common/widgets/loading_widget.dart';
import 'package:tucao/models/video.dart';
import 'package:tucao/pages/reply/reply_page.dart';
import 'package:tucao/pages/video/widgets/player_view.dart';
import 'package:tucao/pages/video/widgets/video_action.dart';
import 'package:tucao/pages/video/widgets/video_info.dart';
import 'package:tucao/plugin/player/player_controller.dart';
import 'package:tucao/router/routes.dart';
import 'package:tucao/utils/storage_pref.dart';

/// 视频播放页.
///
/// 路由参数 `hid` 与可选的 `part` (分P序号, 从 0 开始).
class VideoPage extends StatefulWidget {
  const VideoPage({super.key});

  /// 从列表页进入, 视频信息由播放页重新拉取.
  static void open(VideoModel video, {int part = 0}) {
    Get.toNamed(
      Routes.video,
      parameters: {'hid': video.hid, 'part': part.toString()},
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

class _VideoPageState extends State<VideoPage> with WidgetsBindingObserver {
  late final PlayerPageController _controller;

  /// 是否处于横屏全屏.
  bool _fullscreen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final parameters = Get.parameters;
    final hid = parameters['hid'] ?? '';
    final part = int.tryParse(parameters['part'] ?? '') ?? 0;
    _controller = Get.put(PlayerPageController(hid: hid, part: part), tag: hid);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.detachDanmaku();
    Get.delete<PlayerPageController>(tag: _controller.hid);
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
    return PopScope(
      canPop: !_fullscreen,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _fullscreen) {
          _exitFullscreen();
        }
      },
      child: _fullscreen ? _buildFullscreen() : _buildPortrait(),
    );
  }

  Widget _buildFullscreen() {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(child: _buildPlayerView()),
          SafeArea(
            child: IconButton(
              onPressed: _exitFullscreen,
              icon: const Icon(Icons.arrow_back, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPortrait() {
    return Scaffold(
      appBar: AppBar(
        title: Obx(
          () => Text(
            _controller.video.value?.title ?? '视频',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 15),
          ),
        ),
      ),
      body: Obx(() {
        final error = _controller.error.value;
        if (error != null && _controller.video.value == null) {
          return ErrorWidgetView(message: error, onRetry: _controller.load);
        }
        return Column(
          children: [
            AspectRatio(aspectRatio: 16 / 9, child: _buildPlayerView()),
            Expanded(child: _buildContent()),
          ],
        );
      }),
    );
  }

  Widget _buildPlayerView() {
    return VideoPlayerView(
      controller: _controller,
      fullscreen: _fullscreen,
      onToggleFullscreen: _fullscreen ? _exitFullscreen : _enterFullscreen,
    );
  }

  Widget _buildContent() {
    final video = _controller.video.value;
    if (video == null) {
      return _controller.firstLoading.value
          ? const LoadingWidget()
          : const EmptyWidget(message: '视频信息加载失败');
    }
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        VideoInfoPanel(controller: _controller),
        const Divider(),
        VideoPartBar(controller: _controller),
        VideoActionBar(controller: _controller),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.comment_outlined),
          title: const Text('查看评论'),
          trailing: const Icon(Icons.chevron_right),
          onTap: _openReply,
        ),
      ],
    );
  }

  void _openReply() {
    Get.to(() => ReplyPage(hid: _controller.hid, part: _controller.part.value));
  }
}
