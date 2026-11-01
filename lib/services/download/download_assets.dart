import 'package:dio/dio.dart';
import 'package:tucao/common/constants.dart';
import 'package:tucao/http/danmaku_http.dart';
import 'package:tucao/http/video_http.dart';
import 'package:tucao/models/danmaku.dart';
import 'package:tucao/models/video.dart';

/// 缓存附属数据的网络来源, 与媒体传输分开, 便于测试时替换.
abstract class DownloadAssets {
  /// 最新视频详情, 拿不到时返回空.
  Future<VideoModel?> video(String hid);

  Future<List<DanmakuModel>> danmaku(VideoModel video, int part);

  /// 封面原始字节, 没有封面时返回空.
  Future<List<int>?> cover(VideoModel video);
}

/// 走站点接口的实现, 封面用公共客户端拉取.
class SiteDownloadAssets implements DownloadAssets {
  SiteDownloadAssets(this._dio);

  final Dio _dio;

  /// 封面上限, 超过多半不是图片.
  static const _maxCoverBytes = 8 * 1024 * 1024;

  @override
  Future<VideoModel?> video(String hid) async {
    final response = await VideoHttp.view(hid: hid);
    return response.success ? response.result : null;
  }

  @override
  Future<List<DanmakuModel>> danmaku(VideoModel video, int part) =>
      DanmakuHttp.fetch(typeId: video.typeId, hid: video.hid, part: part);

  @override
  Future<List<int>?> cover(VideoModel video) async {
    final uri = Uri.tryParse(video.cover);
    if (uri == null || !uri.hasScheme || !uri.scheme.startsWith('http')) {
      return null;
    }
    final response = await _dio.getUri<List<int>>(
      uri,
      options: Options(
        responseType: ResponseType.bytes,
        headers: {'user-agent': Constants.userAgent},
      ),
    );
    final type = response.headers.value(Headers.contentTypeHeader) ?? '';
    final bytes = response.data;
    if (bytes == null ||
        bytes.isEmpty ||
        bytes.length > _maxCoverBytes ||
        (type.isNotEmpty && !type.startsWith('image/'))) {
      throw FormatException('封面响应无效: $type, ${bytes?.length ?? 0} 字节');
    }
    return bytes;
  }
}
