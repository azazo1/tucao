import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tucao/pages/video/widgets/cast_sheet.dart';
import 'package:tucao/plugin/player/player_controller.dart';
import 'package:tucao/services/cast/proxy.dart';
import 'package:tucao/services/cast/renderer.dart';
import 'package:tucao/services/cast/session.dart';
import 'package:tucao/utils/logger.dart';

/// 播放页的投屏流程, 在线页与离线页共用.
///
/// 负责选设备, 投屏前卸载本地播放, 会话终态时收尾, 退出后从电视进度接着放.
/// 交给转发服务的是远端直链还是本地文件由 [CastSession] 按地址区分.
class CastFlow extends ChangeNotifier {
  CastFlow({required this.controller, required this.toast}) {
    // 切换分P时收起投屏, 否则电视还在放上一个分P.
    _partWorker = ever<int>(controller.part, (_) {
      if (_session != null) {
        unawaited(finish(restore: false));
      }
    });
  }

  final PlayerPageController controller;

  /// 页面提供的提示方式, 页面已销毁时应自行忽略.
  final void Function(String message) toast;

  Worker? _partWorker;

  CastSession? _session;

  /// 投屏前本地是否在播放, 退出投屏时据此决定要不要接着放.
  bool _wasPlaying = false;

  /// 结束投屏时的重入保护: 停止会触发状态通知, 通知里又会回来收尾.
  bool _ending = false;

  bool _disposed = false;

  /// 当前投屏会话, 为空表示没有在投屏.
  CastSession? get session => _session;

  /// 选一台电视并把当前分P投上去.
  Future<void> start(BuildContext context) async {
    final url = controller.playUrl.value;
    final scheme = Uri.tryParse(url)?.scheme;
    if (scheme != 'http' && scheme != 'https' && scheme != 'file') {
      toast('当前视频没有可投屏的地址');
      return;
    }
    final device = await showCastDeviceSheet(context);
    if (device == null || _disposed || _session != null) {
      return;
    }
    final wasPlaying = controller.player.playing;
    final startAt = controller.player.position;
    // 投屏期间本地不再出声; 卸载地址而不是暂停, 免得那条空闲连接失效.
    await controller.releaseForCast();
    if (_disposed) {
      return;
    }
    final session = CastSession(
      device: device,
      renderer: DlnaRenderer(device: device),
      proxy: CastProxy(),
    )..addListener(_onChanged);
    _wasPlaying = wasPlaying;
    _session = session;
    notifyListeners();
    Log.i('开始投屏到 ${device.name} ${device.location}');
    await session.start(
      mediaUrl: url,
      title: controller.video.value?.title ?? '视频',
      startAt: startAt,
    );
  }

  /// 会话进入终态时收尾, 进度变化交给界面自己监听, 不整页重建.
  void _onChanged() {
    final session = _session;
    if (session == null) {
      return;
    }
    switch (session.state) {
      case CastState.failed:
        unawaited(finish(restore: true, message: session.error ?? '投屏失败'));
      case CastState.finished:
        unawaited(finish(restore: true));
      default:
        break;
    }
  }

  /// 收起投屏, [restore] 为真时把本地播放接回来.
  Future<void> finish({required bool restore, String? message}) async {
    final session = _session;
    if (session == null || _ending) {
      return;
    }
    _ending = true;
    session.removeListener(_onChanged);
    final position = session.position;
    final wasPlaying = _wasPlaying;
    _session = null;
    if (!_disposed) {
      notifyListeners();
    }
    try {
      if (session.state != CastState.finished) {
        await session.stop();
      }
    } catch (error, stackTrace) {
      Log.e('停止投屏失败', error: error, stackTrace: stackTrace);
    } finally {
      session.dispose();
      _ending = false;
    }
    if (message != null) {
      toast(message);
    }
    if (!restore || _disposed) {
      return;
    }
    // 从电视端停下的位置接着放, 与原生客户端的投屏体验一致.
    // 重新打开地址而不是 seek: 旧连接在投屏期间可能已经被服务端断开.
    await controller.resumeAfterCast(position, autoPlay: wasPlaying);
  }

  @override
  void dispose() {
    _disposed = true;
    _partWorker?.dispose();
    _partWorker = null;
    final session = _session;
    _session = null;
    if (session != null && !_ending) {
      session.removeListener(_onChanged);
      unawaited(session.stop().whenComplete(session.dispose));
    }
    super.dispose();
  }
}

/// 顶栏的投屏按钮, 投屏中变成退出投屏.
class CastButton extends StatelessWidget {
  const CastButton({super.key, required this.flow});

  final CastFlow flow;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: flow,
      builder: (context, _) {
        if (flow.session != null) {
          return IconButton(
            tooltip: '退出投屏',
            icon: const Icon(Icons.cast_connected),
            onPressed: () => unawaited(flow.finish(restore: true)),
          );
        }
        return IconButton(
          tooltip: '投屏',
          icon: const Icon(Icons.cast),
          onPressed: () => unawaited(flow.start(context)),
        );
      },
    );
  }
}
