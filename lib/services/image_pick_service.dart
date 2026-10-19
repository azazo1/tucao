import 'dart:typed_data';

import 'package:flutter/services.dart';

/// 用户选中并读进内存的图片.
class PickedImage {
  const PickedImage({required this.bytes, required this.fileName});

  /// 原始字节, 不做压缩, 大小上限由调用方判断.
  final Uint8List bytes;

  /// 系统里显示的文件名, 带后缀, 上传时站点按它认图片类型.
  final String fileName;
}

/// 从系统里挑一张本地图片.
///
/// Android 侧走 ACTION_OPEN_DOCUMENT, 不需要申请存储权限, 选中后由平台侧
/// 读出原始字节再交给 Dart. 用户取消时返回 null.
abstract final class ImagePickService {
  static const _channel = MethodChannel('com.azazo1.tucao/image_picker');

  /// 打开选择器, 用户没选图时返回 null.
  static Future<PickedImage?> pick() async {
    // 平台侧返回的是标准的 map 编码, 这里按动态类型取, 避免泛型 map 的强转
    // 在部分平台上失败.
    final result = await _channel.invokeMethod<Object?>('pickImage');
    if (result is! Map) {
      return null;
    }
    final bytes = result['bytes'];
    if (bytes is! Uint8List || bytes.isEmpty) {
      return null;
    }
    final name = result['name']?.toString().trim() ?? '';
    return PickedImage(
      bytes: bytes,
      fileName: name.isEmpty ? 'image.jpg' : name,
    );
  }
}
