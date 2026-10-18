import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:tucao/common/constants.dart';
import 'package:tucao/utils/logger.dart';
import 'package:tucao/utils/storage_pref.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// 请求代次同时约束回调提交和串行操作, 关闭后不再接受任务.
class PlayerRequestGate {
  int _generation = 0;
  bool _closed = false;
  Future<void> _tail = Future<void>.value();

  int get current => _generation;

  int begin() => ++_generation;

  bool isCurrent(int generation) => !_closed && generation == _generation;

  Future<void> run(int generation, Future<void> Function() operation) {
    final result = _tail.then((_) async {
      if (isCurrent(generation)) {
        await operation();
      }
    });
    // 单个任务失败不能阻塞后续新请求, 错误仍交给任务调用方.
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  void close() {
    _closed = true;
    ++_generation;
  }

  Future<void> get idle => _tail;
}

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
  Future<void>? _initializing;
  final _requests = PlayerRequestGate();

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

  /// 当前视频画面宽度, 还没解析出视频轨时为空.
  int? get videoWidth {
    final width = _player?.state.width;
    return width != null && width > 0 ? width : null;
  }

  /// 当前视频画面高度, 为空时调用方按 16:9 处理.
  int? get videoHeight {
    final height = _player?.state.height;
    return height != null && height > 0 ? height : null;
  }

  /// 创建播放器, 重复调用无副作用.
  ///
  /// 倍速取自 [Pref.playerSpeed], 硬件解码取自 [Pref.hardwareDecode].
  Future<void> init() {
    if (_disposed) {
      return Future<void>.value();
    }
    // 多个调用必须等待同一份完整初始化, 不能仅判断 _player 非空.
    return _initializing ??= _init();
  }

  Future<void> _init() async {
    final player = Player(
      configuration: const PlayerConfiguration(title: 'tucao'),
    );
    _player = player;
    _videoController = VideoController(
      player,
      configuration: VideoControllerConfiguration(
        enableHardwareAcceleration: Pref.hardwareDecode,
      ),
    );
    _speed = Pref.playerSpeed;
    _volume = Pref.playerVolume;
    _subscribe();
    await player.setRate(_speed);
    if (_disposed) {
      return;
    }
    await player.setVolume(_volume);
    if (_disposed) {
      return;
    }
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
    if (_disposed) {
      return;
    }
    final request = _requests.begin();
    await _requests.run(request, () async {
      await init();
      if (!_requests.isCurrent(request)) {
        return;
      }
      final player = _player!;
      Log.i('加载播放地址: $url');
      _completed = false;
      _error = null;
      _playing = false;
      _buffering = false;
      _position = Duration.zero;
      _notifiedPosition = Duration.zero;
      _duration = Duration.zero;
      _buffered = Duration.zero;
      _notify();
      await player.open(Media(url, httpHeaders: _headers), play: autoPlay);
      if (!_requests.isCurrent(request)) {
        return;
      }
      // open 会重置部分播放属性, 重新应用倍速和音量.
      await player.setRate(_speed);
      if (!_requests.isCurrent(request)) {
        return;
      }
      await player.setVolume(_volume);
      if (!_requests.isCurrent(request)) {
        return;
      }
      if (startAt != null && startAt > Duration.zero) {
        await player.seek(startAt);
      }
    });
  }

  Future<void> _control(Future<void> Function(Player) operation) {
    final request = _requests.current;
    return _requests.run(request, () async {
      await _initializing;
      final player = _player;
      if (_requests.isCurrent(request) && player != null) {
        await operation(player);
      }
    });
  }

  Future<void> play() async {
    Log.d('播放');
    await _control((player) => player.play());
  }

  Future<void> pause() async {
    Log.d('暂停');
    await _control((player) => player.pause());
  }

  Future<void> toggle() async {
    if (_playing) {
      await pause();
    } else {
      await play();
    }
  }

  Future<void> seek(Duration position) async {
    Log.d('跳转到 ${position.inMilliseconds}ms');
    await _control((player) => player.seek(position));
  }

  /// 卸载当前地址, 播放器本身仍可继续使用.
  Future<void> stop() async {
    if (_disposed) {
      return;
    }
    final request = _requests.begin();
    await _requests.run(request, () async {
      await _initializing;
      if (!_requests.isCurrent(request)) {
        return;
      }
      await _player?.stop();
      if (!_requests.isCurrent(request)) {
        return;
      }
      _playing = false;
      _buffering = false;
      _error = null;
      _position = Duration.zero;
      _notifiedPosition = Duration.zero;
      _duration = Duration.zero;
      _buffered = Duration.zero;
      _completed = false;
      _notify();
    });
  }

  /// 设置倍速, 同时写回用户偏好.
  Future<void> setSpeed(double speed) async {
    if (_disposed || speed <= 0) {
      return;
    }
    _speed = speed;
    Pref.playerSpeed = speed;
    Log.i('倍速调整为 ${speed.toStringAsFixed(2)}');
    await _control((player) => player.setRate(speed));
    _notify();
  }

  /// 设置音量, 取值范围 0 - 100.
  Future<void> setVolume(double volume) async {
    if (_disposed) {
      return;
    }
    _volume = volume.clamp(0, 100);
    Pref.playerVolume = _volume;
    await _control((player) => player.setVolume(_volume));
    _notify();
  }

  void _subscribe() {
    final player = _player!;
    _subscriptions.addAll([
      player.stream.playing.listen((value) {
        if (_disposed) {
          return;
        }
        _playing = value;
        _updateWakelock();
        _notify();
      }),
      player.stream.completed.listen((value) {
        if (_disposed) {
          return;
        }
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
        if (_disposed) {
          return;
        }
        _position = value;
        // 跳转时位置变化很大, 需要立即上报.
        if ((value - _notifiedPosition).abs() >= _positionStep) {
          _notifiedPosition = value;
          _notify();
        }
      }),
      player.stream.duration.listen((value) {
        if (_disposed) {
          return;
        }
        _duration = value;
        _notify();
      }),
      player.stream.buffer.listen((value) {
        if (_disposed) {
          return;
        }
        _buffered = value;
        _notify();
      }),
      player.stream.buffering.listen((value) {
        if (_disposed) {
          return;
        }
        _buffering = value;
        _notify();
      }),
      player.stream.rate.listen((value) {
        if (_disposed) {
          return;
        }
        _speed = value;
        _notify();
      }),
      player.stream.error.listen((value) {
        if (_disposed) {
          return;
        }
        final message = value.trim();
        if (message.isEmpty) {
          return;
        }
        // 硬件解码器打不开时 mpv 会回退到软件解码继续播放,
        // 这类 error 级别的日志不是播放失败, 不应该盖住正常画面.
        if (_isRecoverableError(message)) {
          Log.w('播放器解码回退: $message');
          return;
        }
        _error = message;
        _buffering = false;
        Log.e('播放出错: $message');
        _notify();
      }),
    ]);
  }

  /// 判断播放器错误是否只是解码器回退, 不影响继续播放.
  static bool _isRecoverableError(String message) {
    final lower = message.toLowerCase();
    return lower.contains('could not open codec');
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
    _requests.close();
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
    unawaited(WakelockPlus.disable().catchError((Object error) {}));
    // 在途原生调用结束后再释放, 不与 open/init 竞争.
    unawaited(_release());
    Log.i('播放器已释放');
    super.dispose();
  }

  Future<void> _release() async {
    try {
      await _requests.idle;
      await _initializing;
    } catch (e, stackTrace) {
      Log.e('播放器初始化未完成', error: e, stackTrace: stackTrace);
    }
    final player = _player;
    _player = null;
    _videoController = null;
    try {
      await player?.dispose();
    } catch (e, stackTrace) {
      Log.e('释放播放器失败', error: e, stackTrace: stackTrace);
    }
  }
}
