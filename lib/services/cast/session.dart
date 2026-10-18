import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:tucao/models/cast_device.dart';
import 'package:tucao/services/cast/cast_exception.dart';
import 'package:tucao/services/cast/proxy.dart';
import 'package:tucao/services/cast/renderer.dart';
import 'package:tucao/utils/logger.dart';

/// 一次投屏的状态.
enum CastState {
  /// 还没有投屏.
  idle,

  /// 正在把地址交给电视.
  connecting,

  /// 电视在播放.
  playing,

  /// 电视暂停.
  paused,

  /// 出错, 例如电视拒绝播放或者网络断开.
  failed,

  /// 电视端已经停止, 通常是用户按了遥控器.
  finished,
}

/// 一次投屏会话: 负责下发地址, 轮询进度, 以及退出时收拾现场.
///
/// 会话不碰本地播放器, 开始与结束时的本地暂停与续播交给页面处理.
class CastSession extends ChangeNotifier {
  CastSession({
    required this.device,
    required this.renderer,
    required this.proxy,
    this.pollInterval = const Duration(seconds: 1),
    this.seekGuard = const Duration(seconds: 3),
  });

  final CastDevice device;

  final DlnaRenderer renderer;

  final CastProxy proxy;

  final Duration pollInterval;

  /// 跳转后多久内不接受轮询位置, 避免进度条先弹回旧位置.
  final Duration seekGuard;

  CastState _state = CastState.idle;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  String? _error;
  Timer? _poller;
  bool _polling = false;
  int _failures = 0;
  bool _disposed = false;

  /// 转发地址与标题, 电视不认 Seek 时按它们重开一遍.
  String? _proxyUrl;
  String _title = '视频';

  /// 跳转后的短暂窗口, 这段时间不拿轮询位置覆盖界面, 避免游标弹回原处.
  DateTime? _seekGuard;

  CastState get state => _state;

  Duration get position => _position;

  Duration get duration => _duration;

  String? get error => _error;

  /// 投屏是否仍在进行, 包括连接中与暂停.
  bool get active =>
      _state == CastState.connecting ||
      _state == CastState.playing ||
      _state == CastState.paused;

  /// 需要页面把本地播放接回来.
  bool get ended =>
      _state == CastState.idle ||
      _state == CastState.finished ||
      _state == CastState.failed;

  /// 开始投屏, [startAt] 是本地当前进度, 投上去后从那里接着放.
  Future<void> start({
    required String mediaUrl,
    required String title,
    Duration startAt = Duration.zero,
  }) async {
    _setState(CastState.connecting);
    try {
      final url = await proxy.register(mediaUrl);
      Log.i('投屏地址 ${url.host}:${url.port} -> $mediaUrl');
      _proxyUrl = url.toString();
      _title = title;
      await renderer.setMedia(_proxyUrl!, title: title);
      await renderer.play();
      if (startAt > const Duration(seconds: 2)) {
        await renderer.seek(startAt);
      }
      _position = startAt;
      _setState(CastState.playing);
      _startPolling();
    } catch (error) {
      Log.w('投屏失败: $error');
      _error = _describe(error);
      _setState(CastState.failed);
      await proxy.close();
    }
  }

  Future<void> pause() async {
    if (!active) {
      return;
    }
    try {
      await renderer.pause();
      final info = await renderer.fetchPlayback();
      _position = info.position;
      _setState(CastState.paused);
    } catch (error) {
      Log.w('投屏暂停失败: $error');
      _error = _describe(error);
      _setState(CastState.failed);
    }
  }

  Future<void> resume() async {
    if (!active) {
      return;
    }
    try {
      await renderer.play();
      _setState(CastState.playing);
    } catch (error) {
      Log.w('投屏继续播放失败: $error');
      _error = _describe(error);
      _setState(CastState.failed);
    }
  }

  /// 在手机上拖动进度.
  ///
  /// 大多数电视能直接接 Seek; 少数只认重开, 这里失败后退回
  /// 停止 -> 重新下发地址 -> 播放 -> 跳转 的流程.
  Future<void> seek(Duration position) async {
    if (!active) {
      return;
    }
    final target = Duration(
      milliseconds: position.inMilliseconds.clamp(0, 1 << 40),
    );
    try {
      await renderer.seek(target);
      _markSeeked(target);
    } catch (error) {
      Log.w('电视不接受 Seek, 改为重开播放: $error');
      try {
        await _restartAt(target);
      } catch (restartError) {
        Log.w('重开播放也失败: $restartError');
        _error = _describe(restartError);
        _setState(CastState.failed);
      }
    }
  }

  /// 停掉当前媒体, 从 [target] 重新开始, 暂停状态会被保留.
  Future<void> _restartAt(Duration target) async {
    final url = _proxyUrl;
    if (url == null) {
      throw const CastException('没有可重开的地址');
    }
    final wasPaused = _state == CastState.paused;
    await renderer.stop();
    await renderer.setMedia(url, title: _title);
    await renderer.play();
    await renderer.seek(target);
    if (wasPaused) {
      await renderer.pause();
    }
    _markSeeked(target);
    if (wasPaused) {
      _setState(CastState.paused);
    }
  }

  /// 记录跳转结果, 并在短时间内不让轮询位置把界面拉回去.
  void _markSeeked(Duration target) {
    _position = target;
    _seekGuard = DateTime.now().add(seekGuard);
    notifyListeners();
  }

  /// 主动结束投屏, 同时让电视停下来.
  Future<void> stop() async {
    _stopPolling();
    try {
      await renderer.stop();
    } catch (error) {
      Log.w('停止投屏失败: $error');
    }
    await proxy.close();
    _setState(CastState.idle);
  }

  void _startPolling() {
    _stopPolling();
    _failures = 0;
    _poller = Timer.periodic(pollInterval, (_) => unawaited(_poll()));
  }

  void _stopPolling() {
    _poller?.cancel();
    _poller = null;
  }

  Future<void> _poll() async {
    if (_disposed || _polling || !active) {
      return;
    }
    _polling = true;
    try {
      final info = await renderer.fetchPlayback();
      _failures = 0;
      final guard = _seekGuard;
      if (guard == null || DateTime.now().isAfter(guard)) {
        _seekGuard = null;
        _position = info.position;
      }
      if (info.duration > Duration.zero) {
        _duration = info.duration;
      }
      switch (info.state) {
        case 'PLAYING':
          _state = CastState.playing;
        case 'PAUSED_PLAYBACK':
          _state = CastState.paused;
        case 'STOPPED':
        case 'NO_MEDIA_PRESENT':
          // 电视端被遥控器停下, 这里把会话收尾, 让页面接回本地播放.
          _stopPolling();
          await proxy.close();
          _state = CastState.finished;
        default:
          break;
      }
      notifyListeners();
    } catch (error) {
      _failures++;
      Log.w('投屏状态轮询失败 ($_failures): $error');
      if (_failures >= 3) {
        _error = _describe(error);
        _stopPolling();
        await proxy.close();
        _setState(CastState.failed);
      }
    } finally {
      _polling = false;
    }
  }

  void _setState(CastState state) {
    if (_disposed) {
      return;
    }
    _state = state;
    notifyListeners();
  }

  String _describe(Object error) {
    final text = error.toString();
    return text.isEmpty ? '投屏失败' : text;
  }

  @override
  void dispose() {
    _disposed = true;
    _stopPolling();
    renderer.dispose();
    proxy.dispose();
    super.dispose();
  }
}
