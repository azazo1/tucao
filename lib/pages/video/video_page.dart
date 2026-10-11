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

class _VideoPageState extends State<VideoPage> with WidgetsBindingObserver {
  /// 同一视频可能被重复打开, 用实例标识区分控制器.
  late final String _tag = 'video_${identityHashCode(this)}';

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
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
      child: Scaffold(
        backgroundColor: _fullscreen
            ? Colors.black
            : Theme.of(context).colorScheme.surface,
        // 全屏时用零高度的占位替代标题栏, 保持 body 的 element 不被重建,
        // 否则切换全屏会重新挂载播放器与弹幕层.
        appBar: _fullscreen ? _emptyAppBar : _buildAppBar(),
        body: LayoutBuilder(
          builder: (context, constraints) {
            // 竖屏下播放器固定为 16:9, 全屏下铺满.
            final playerHeight = _fullscreen
                ? constraints.maxHeight
                : constraints.maxWidth * 9 / 16;
            return Stack(
              children: [
                Positioned(
                  left: 0,
                  top: 0,
                  right: 0,
                  height: playerHeight,
                  child: _buildPlayerView(),
                ),
                if (!_fullscreen)
                  Positioned(
                    left: 0,
                    top: playerHeight,
                    right: 0,
                    bottom: 0,
                    child: _buildContentArea(),
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
      controller: _controller,
      fullscreen: _fullscreen,
      onToggleFullscreen: _fullscreen ? _exitFullscreen : _enterFullscreen,
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
    Get.to(
      () => ReplyPage(
        typeId: _controller.typeId,
        hid: _controller.hid,
        part: _controller.part.value,
      ),
    );
  }
}
