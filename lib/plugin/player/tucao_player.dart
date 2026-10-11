import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:tucao/common/constants.dart';
import 'package:tucao/utils/logger.dart';
import 'package:tucao/utils/storage_pref.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// 基于 media_kit 的播放器封装.
///
/// 只负责播放本身: 加载地址, 播放控制与状态上报.
/// 弹幕投递, 历史记录等业务逻辑放在 PlayerPageController.
/// 切换分P时复用同一个 [Player], 只重新加载地址, 不重建播放器.
class TucaoPlayer extends ChangeNotifier {
  /// 播放到结尾时回调.
  VoidCallback? onCompleted;

  /// 进度回调的最小间隔, 避免进度事件过于频繁地触发界面重建.
  static const _positionStep = Duration(milliseconds: 100);

  /// 站点视频源需要带上的请求头, 部分源会校验来源.
  static final _headers = <String, String>{
    'User-Agent': Constants.userAgent,
    'Referer': Constants.baseUrl,
  };

  Player? _player;
  VideoController? _videoController;

  final _subscriptions = <StreamSubscription<dynamic>>[];

  bool _disposed = false;
  bool _playing = false;
  bool _completed = false;
  bool _buffering = false;
  Duration _position = Duration.zero;
  Duration _notifiedPosition = Duration.zero;
  Duration _duration = Duration.zero;
  Duration _buffered = Duration.zero;
  double _speed = 1;
  double _volume = 100;
  String? _error;

  /// 播放器是否已经创建.
  bool get initialized => _player != null;

  Player get player => _player!;

  VideoController get videoController => _videoController!;

  bool get playing => _playing;

  bool get completed => _completed;

  bool get buffering => _buffering;

  Duration get position => _position;

  Duration get duration => _duration;

  /// 已缓冲到的位置.
  Duration get buffered => _buffered;

  double get speed => _speed;

  double get volume => _volume;

  String? get error => _error;

  /// 创建播放器, 重复调用无副作用.
  ///
  /// 倍速取自 [Pref.playerSpeed], 硬件解码取自 [Pref.hardwareDecode].
  Future<void> init() async {
    if (_player != null) {
      return;
    }
    _player = Player(configuration: const PlayerConfiguration(title: 'tucao'));
    _videoController = VideoController(
      _player!,
      configuration: VideoControllerConfiguration(
        enableHardwareAcceleration: Pref.hardwareDecode,
      ),
    );
    _speed = Pref.playerSpeed;
    _volume = Pref.playerVolume;
    _subscribe();
    await _player!.setRate(_speed);
    await _player!.setVolume(_volume);
    Log.i(
      '播放器初始化完成, 硬件解码 ${Pref.hardwareDecode ? '开启' : '关闭'}, '
      '倍速 ${_speed.toStringAsFixed(2)}, 音量 ${_volume.toStringAsFixed(0)}',
    );
    _notify();
  }

  /// 加载播放地址.
  ///
  /// [startAt] 不为空时从该位置开始播放, 用于续播上次进度.
  Future<void> setUrl(
    String url, {
    bool autoPlay = true,
    Duration? startAt,
  }) async {
    await init();
    Log.i('加载播放地址: $url');
    _completed = false;
    _error = null;
    _position = Duration.zero;
    _notifiedPosition = Duration.zero;
    _duration = Duration.zero;
    _buffered = Duration.zero;
    _notify();
    await _player!.open(Media(url, httpHeaders: _headers), play: autoPlay);
    // open 会重置部分播放属性, 这里重新应用倍速与音量.
    await _player!.setRate(_speed);
    await _player!.setVolume(_volume);
    if (startAt != null && startAt > Duration.zero) {
      await _player!.seek(startAt);
    }
  }

  Future<void> play() async {
    if (_player == null) {
      return;
    }
    Log.d('播放');
    await _player!.play();
  }

  Future<void> pause() async {
    if (_player == null) {
      return;
    }
    Log.d('暂停');
    await _player!.pause();
  }

  Future<void> toggle() async {
    if (_playing) {
      await pause();
    } else {
      await play();
    }
  }

  Future<void> seek(Duration position) async {
    if (_player == null) {
      return;
    }
    Log.d('跳转到 ${position.inMilliseconds}ms');
    await _player!.seek(position);
  }

  /// 卸载当前地址, 播放器本身仍可继续使用.
  Future<void> stop() async {
    if (_player == null) {
      return;
    }
    await _player!.stop();
    _position = Duration.zero;
    _notifiedPosition = Duration.zero;
    _duration = Duration.zero;
    _buffered = Duration.zero;
    _completed = false;
    _notify();
  }

  /// 设置倍速, 同时写回用户偏好.
  Future<void> setSpeed(double speed) async {
    if (speed <= 0) {
      return;
    }
    _speed = speed;
    Pref.playerSpeed = speed;
    Log.i('倍速调整为 ${speed.toStringAsFixed(2)}');
    await _player?.setRate(speed);
    _notify();
  }

  /// 设置音量, 取值范围 0 - 100.
  Future<void> setVolume(double volume) async {
    _volume = volume.clamp(0, 100);
    Pref.playerVolume = _volume;
    await _player?.setVolume(_volume);
    _notify();
  }

  void _subscribe() {
    final player = _player!;
    _subscriptions.addAll([
      player.stream.playing.listen((value) {
        _playing = value;
        _updateWakelock();
        _notify();
      }),
      player.stream.completed.listen((value) {
        if (_completed == value) {
          return;
        }
        _completed = value;
        if (value) {
          Log.i('播放结束');
          onCompleted?.call();
        }
        _notify();
      }),
      player.stream.position.listen((value) {
        _position = value;
        // 跳转时位置变化很大, 需要立即上报.
        if ((value - _notifiedPosition).abs() >= _positionStep) {
          _notifiedPosition = value;
          _notify();
        }
      }),
      player.stream.duration.listen((value) {
        _duration = value;
        _notify();
      }),
      player.stream.buffer.listen((value) {
        _buffered = value;
        _notify();
      }),
      player.stream.buffering.listen((value) {
        _buffering = value;
        _notify();
      }),
      player.stream.rate.listen((value) {
        _speed = value;
        _notify();
      }),
      player.stream.error.listen((value) {
        _error = value;
        Log.e('播放出错: $value');
        _notify();
      }),
    ]);
  }

  /// 播放中阻止息屏, 暂停或释放时取消.
  void _updateWakelock() {
    unawaited(
      (_playing ? WakelockPlus.enable() : WakelockPlus.disable()).catchError((
        Object error,
      ) {
        Log.w('息屏控制失败: $error');
      }),
    );
  }

  void _notify() {
    if (_disposed) {
      return;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _subscriptions.clear();
    unawaited(WakelockPlus.disable().catchError((Object error) {}));
    _player?.dispose();
    _player = null;
    _videoController = null;
    Log.i('播放器已释放');
    super.dispose();
  }
}
