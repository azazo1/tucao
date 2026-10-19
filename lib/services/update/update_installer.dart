import 'package:flutter/services.dart';
import 'package:tucao/utils/logger.dart';

/// 安装包安装的平台通道封装.
///
/// 负责三件事: 读取设备支持的 ABI, 查询是否已经允许安装未知应用,
/// 以及把下载好的安装包交给系统安装器.
///
/// 平台不可用或调用失败时一律按失败处理, 不向调用方抛异常: 这样 widget
/// 测试等没有插件的场合不用额外打桩, 界面也只是提示无法安装.
abstract final class UpdateInstaller {
  /// 平台通道名, 与 MainActivity 中注册的一致.
  static const _channel = MethodChannel('com.azazo1.tucao/apk_installer');

  /// 本机支持的 ABI, 按系统的优先顺序排列; 读不到时返回空列表.
  static Future<List<String>> supportedAbis() async {
    try {
      final abis = await _channel.invokeMethod<List<Object?>>('supportedAbis');
      return abis?.whereType<String>().toList(growable: false) ?? const [];
    } catch (error) {
      Log.w('读取设备 ABI 失败: $error');
      return const [];
    }
  }

  /// 系统是否已经允许本应用安装安装包.
  static Future<bool> canInstall() async {
    try {
      return await _channel.invokeMethod<bool>('canInstall') ?? false;
    } catch (error) {
      Log.w('查询安装权限失败: $error');
      return false;
    }
  }

  /// 打开"安装未知应用"的系统设置页, 让用户为本应用放行.
  static Future<bool> openInstallSettings() async {
    try {
      return await _channel.invokeMethod<bool>('openInstallSettings') ?? false;
    } catch (error) {
      Log.w('打开安装权限设置失败: $error');
      return false;
    }
  }

  /// 用系统安装器打开 [path] 指向的安装包.
  static Future<bool> install(String path) async {
    try {
      return await _channel.invokeMethod<bool>('install', {'path': path}) ??
          false;
    } catch (error) {
      Log.w('启动系统安装器失败: $error');
      return false;
    }
  }
}
