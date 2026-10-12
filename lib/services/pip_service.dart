import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:tucao/utils/logger.dart';

/// 安卓画中画 (Picture-in-Picture) 的平台通道封装.
///
/// 负责三件事: 查询设备是否支持, 请求进入小窗, 以及把 "回到桌面时自动进入"
/// 的开关与画面宽高比交给系统. 小窗状态由平台侧回调, 通过 [inPipMode]
/// 暴露给界面.
///
/// 平台不可用或调用失败时一律按不支持处理, 不向调用方抛异常: 这样 widget
/// 测试等没有插件的场合不用额外打桩, 界面也只是不显示入口.
class PipService {
  PipService._() {
    _channel.setMethodCallHandler(_onPlatformCall);
  }

  /// 全局唯一实例.
  static final PipService instance = PipService._();

  /// 平台通道名, 与 MainActivity 中注册的一致.
  static const _channel = MethodChannel('com.azazo1.tucao/pip');

  /// 当前是否处于小窗, 播放页据此切换布局.
  final inPipMode = ValueNotifier(false);

  /// 查询设备是否支持画中画.
  ///
  /// 调用点只有设置页与播放页各一次, 每次都直接问平台, 不做缓存.
  Future<bool> isSupported() async {
    final supported = await _invoke<bool>('isSupported');
    return supported ?? false;
  }

  /// 请求进入小窗.
  ///
  /// [width] 与 [height] 是当前视频画面尺寸, 省略时平台侧沿用上一次的宽高比.
  /// [sourceRect] 是小窗动画的起点, 用设备像素表示, 省略时交给系统决定.
  Future<bool> enter({int? width, int? height, Rect? sourceRect}) async {
    final arguments = _arguments(
      width: width,
      height: height,
      sourceRect: sourceRect,
    );
    final entered = await _invoke<bool>('enter', arguments);
    return entered ?? false;
  }

  /// 设置回到桌面等场景下是否自动进入小窗.
  ///
  /// 平台侧在 Android 12 及以上把时机交给系统参数, 更低版本自行判断.
  Future<void> setAutoEnter({
    required bool enabled,
    int? width,
    int? height,
  }) async {
    final arguments = _arguments(width: width, height: height);
    await _invoke<bool>('setAutoEnter', {...arguments, 'enabled': enabled});
  }

  /// 平台回调: 小窗状态变化.
  Future<void> _onPlatformCall(MethodCall call) async {
    if (call.method == 'pipModeChanged') {
      inPipMode.value = call.arguments == true;
    }
  }

  /// 组装通道参数, 尺寸不合法时不传, 由平台侧沿用默认宽高比.
  Map<String, Object> _arguments({int? width, int? height, Rect? sourceRect}) {
    return {
      if (width != null && height != null && width > 0 && height > 0) ...{
        'width': width,
        'height': height,
      },
      if (sourceRect != null) ...{
        'left': sourceRect.left.round(),
        'top': sourceRect.top.round(),
        'right': sourceRect.right.round(),
        'bottom': sourceRect.bottom.round(),
      },
    };
  }

  /// 通道调用失败一律降级为不可用, 不打断界面.
  Future<T?> _invoke<T>(String method, [Map<String, Object>? arguments]) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on MissingPluginException {
      return null;
    } on PlatformException catch (error) {
      Log.w('画中画调用 $method 失败: ${error.message}');
      return null;
    }
  }
}
