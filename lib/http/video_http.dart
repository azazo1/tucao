import 'package:dio/dio.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:tucao/common/constants.dart';
import 'package:tucao/http/api_path.dart';
import 'package:tucao/models/api_response.dart';
import 'package:tucao/models/video.dart';
import 'package:tucao/models/video_subject.dart';
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

  /// 拉取站点播放页, 同时解析完整简介与番组信息.
  ///
  /// 详情接口的 description 只返回截断的一段, 播放页的 `.show_content`
  /// 才是完整正文, 同一页面的 `.vdata_info .b` 里还有类型, 别名, 首播,
  /// 原作, 导演, 角色配音等番组信息, 因此一次请求拿回两样.
  static Future<VideoPlayPageDetail> fetchPlayPage({
    required String hid,
    CancelToken? cancelToken,
  }) async {
    final response = await HttpUtil.dio.get(
      ApiPath.playUrl(hid),
      cancelToken: cancelToken,
      options: Options(headers: {'user-agent': Constants.desktopUserAgent}),
    );
    final raw = response.data.toString();
    return VideoPlayPageDetail(
      description: parseDescriptionHtml(raw),
      subject: parseSubjectInfoHtml(raw),
    );
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

  /// 解析播放页里的番组信息.
  ///
  /// 播放页把类型, 别名, 年代, 首播, 原作, 导演, 角色配音, 制作公司等
  /// 放在 `.vdata_info .b` 里, 格式是 `<span class="n">标签：</span>值<br />`.
  /// 不同条目字段不完全相同, 这里按页面顺序保留, 不写死字段名.
  static VideoSubjectInfo parseSubjectInfoHtml(String raw) {
    final document = html_parser.parse(raw);
    final node = document.querySelector('.vdata_info .b');
    if (node == null) {
      return VideoSubjectInfo.empty;
    }

    final fields = <SubjectField>[];
    String? label;
    final buffer = StringBuffer();

    void flush() {
      final name = label?.trim();
      final value = _normalizeSubjectValue(buffer.toString());
      if (name != null && name.isNotEmpty && value.isNotEmpty) {
        fields.add(SubjectField(label: name, value: value));
      }
      label = null;
      buffer.clear();
    }

    for (final child in node.nodes) {
      if (child is dom.Element) {
        if (child.localName == 'br') {
          flush();
          continue;
        }
        if (child.classes.contains('n')) {
          // 前一项的值到此结束, 这个元素本身是下一项的标签.
          flush();
          label = child.text.replaceAll(RegExp(r'[：:]\s*$'), '').trim();
          continue;
        }
        // 链接等行内元素的值取文本, 声优名单就是多个链接拼起来的.
        buffer.write(child.text);
        continue;
      }
      if (child is dom.Text) {
        buffer.write(child.text);
      }
    }
    flush();
    return VideoSubjectInfo(fields);
  }

  static String _normalizeSubjectValue(String raw) =>
      raw.replaceAll(RegExp(r'\s+'), ' ').trim();

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
