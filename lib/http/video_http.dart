import 'package:dio/dio.dart';
import 'package:tucao/common/constants.dart';
import 'package:tucao/http/api_path.dart';
import 'package:tucao/models/api_response.dart';
import 'package:tucao/models/video.dart';
import 'package:tucao/utils/http_util.dart';

/// 视频相关的接口.
abstract final class VideoHttp {
  /// 分区视频列表.
  ///
  /// [order] 支持 date, mukio, views, 留空时站点按默认排序.
  static Future<ListResponse<VideoModel>> list({
    required int typeId,
    required int page,
    int pageSize = 20,
    String? order,
    CancelToken? cancelToken,
  }) async {
    final response = await HttpUtil.dio.get(
      '${Constants.apiUrl}${ApiPath.list}',
      queryParameters: {
        'tid': typeId,
        'page': page,
        'pagesize': pageSize,
        'order': order ?? 'date',
        'apikey': Constants.apiKey,
      },
      cancelToken: cancelToken,
    );
    return ListResponse.fromJson(
      HttpUtil.decodeJson(response.data.toString()),
      VideoModel.fromJson,
    );
  }

  /// 视频详情.
  static Future<ApiResponse<VideoModel>> view({
    required String hid,
    CancelToken? cancelToken,
  }) async {
    final response = await HttpUtil.dio.get(
      '${Constants.apiUrl}${ApiPath.view}',
      queryParameters: {'hid': hid, 'apikey': Constants.apiKey},
      cancelToken: cancelToken,
    );
    return ApiResponse.fromJson(
      HttpUtil.decodeJson(response.data.toString()),
      (data) => VideoModel.fromJson((data as Map).cast<String, dynamic>()),
    );
  }

  /// 关键词搜索.
  static Future<ListResponse<VideoModel>> search({
    required String keyword,
    required int page,
    int? typeId,
    int pageSize = 20,
    String? order,
    CancelToken? cancelToken,
  }) async {
    final response = await HttpUtil.dio.get(
      '${Constants.apiUrl}${ApiPath.search}',
      queryParameters: {
        'tid': ?typeId,
        'page': page,
        'pagesize': pageSize,
        'order': order ?? 'date',
        'q': keyword,
        'apikey': Constants.apiKey,
      },
      cancelToken: cancelToken,
    );
    return ListResponse.fromJson(
      HttpUtil.decodeJson(response.data.toString()),
      VideoModel.fromJson,
    );
  }
}
