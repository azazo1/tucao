import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:tucao/utils/http_util.dart';

/// 图片保存.
///
/// 先用网络层把图片下载成字节, 再交给平台侧写进系统相册.
/// Android 10 起写的是 MediaStore, 不需要申请存储权限; 更早的系统会落到
/// 应用自己的图片目录, 所以返回值就是"保存到哪"的提示文案, 不要自己编.
abstract final class ImageSaveService {
  static const _channel = MethodChannel('com.azazo1.tucao/image_saver');

  /// 允许的图片后缀, 其余一律按 jpg 处理.
  static const _imageExtensions = {'.jpg', '.jpeg', '.png', '.gif', '.webp'};

  /// 下载并保存, 返回保存位置.
  static Future<String> saveUrl(String url, {String prefix = 'tucao'}) async {
    final bytes = await _download(url);
    return save(bytes, fileName: fileNameFor(url, prefix: prefix));
  }

  /// 把字节交给平台侧写入相册.
  static Future<String> save(
    Uint8List bytes, {
    required String fileName,
  }) async {
    final location = await _channel.invokeMethod<String>('save', {
      'bytes': bytes,
      'fileName': fileName,
    });
    return location ?? fileName;
  }

  /// 按原地址的后缀与调用方给的前缀生成文件名.
  static String fileNameFor(String url, {String prefix = 'tucao'}) {
    final segments = Uri.tryParse(url)?.pathSegments ?? const <String>[];
    final origin = segments.isEmpty ? '' : segments.last;
    final dot = origin.lastIndexOf('.');
    final ext = dot < 0 ? '' : origin.substring(dot).toLowerCase();
    final suffix = _imageExtensions.contains(ext) ? ext : '.jpg';
    return '${prefix}_${DateTime.now().millisecondsSinceEpoch}$suffix';
  }

  static Future<Uint8List> _download(String url) async {
    final response = await HttpUtil.dio.get<List<int>>(
      url,
      options: Options(
        responseType: ResponseType.bytes,
        validateStatus: (status) =>
            status != null && status >= 200 && status < 400,
      ),
    );
    final bytes = response.data;
    if (bytes == null || bytes.isEmpty) {
      throw Exception('图片下载失败');
    }
    return Uint8List.fromList(bytes);
  }
}
