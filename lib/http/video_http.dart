import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:tucao/common/constants.dart';
import 'package:tucao/http/api_path.dart';
import 'package:tucao/models/api_response.dart';
import 'package:tucao/models/video.dart';
import 'package:tucao/utils/html_text.dart';
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

  /// 拉取站点播放页里的完整简介.
  ///
  /// 详情接口的 description 只返回截断的一段, 播放页的 `.show_content`
  /// 才是完整正文, 因此展开简介时按需再取一次页面.
  static Future<String> fetchDescription({
    required String hid,
    CancelToken? cancelToken,
  }) async {
    final response = await HttpUtil.dio.get(
      ApiPath.playUrl(hid),
      cancelToken: cancelToken,
      options: Options(headers: {'user-agent': Constants.desktopUserAgent}),
    );
    return parseDescriptionHtml(response.data.toString());
  }

  /// 解析播放页里的简介正文, 去掉页面自带的 "简介：" 标签.
  static String parseDescriptionHtml(String raw) {
    final document = html_parser.parse(raw);
    final node = document.querySelector('.show_content');
    if (node == null) {
      return '';
    }
    for (final label in node.querySelectorAll('.show_content_n')) {
      label.remove();
    }
    // 只靠 br 换行时, div 拆出来的段落会粘在一起, 这里补上分段.
    final html = node.innerHtml.replaceAll(
      RegExp(r'</p\s*>', caseSensitive: false),
      '\n',
    );
    return decodeHtmlText(html).trim();
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
