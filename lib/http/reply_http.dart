import 'package:dio/dio.dart';
import 'package:tucao/common/constants.dart';
import 'package:tucao/http/api_path.dart';
import 'package:tucao/models/reply.dart';
import 'package:tucao/utils/http_util.dart';

/// 评论接口.
abstract final class ReplyHttp {
  /// 拉取评论.
  ///
  /// [replyId] 不为空时拉取该评论下的楼中楼回复.
  static Future<ReplyPage> list({
    required String hid,
    required int part,
    int page = 1,
    int pageSize = 20,
    int? replyId,
    bool hot = true,
    CancelToken? cancelToken,
  }) async {
    final response = await HttpUtil.dio.get(
      '${Constants.baseUrl}${ApiPath.replyList}',
      queryParameters: {
        'commentid': ApiPath.commentId(hid, part),
        if (replyId != null) 'replyid': replyId,
        'hot': hot ? 1 : 0,
        'page': page,
        'num': pageSize,
      },
      cancelToken: cancelToken,
    );
    final raw = response.data.toString().trim();
    if (raw.isEmpty || raw == '0') {
      return const ReplyPage(total: 0, list: []);
    }
    return ReplyPage.fromJson(HttpUtil.decodeJson(raw));
  }

  /// 发送评论.
  static Future<String> send({
    required String hid,
    required int part,
    required String content,
    int? replyId,
    CancelToken? cancelToken,
  }) async {
    final response = await HttpUtil.dio.post(
      '${Constants.baseUrl}${ApiPath.replySend}',
      data: {
        'commentid': ApiPath.commentId(hid, part),
        'content': content,
        'replyid': replyId?.toString() ?? '',
      },
      options: Options(contentType: Headers.formUrlEncodedContentType),
      cancelToken: cancelToken,
    );
    return response.data.toString();
  }

  /// 点赞评论.
  static Future<String> support({
    required String commentId,
    required String id,
    CancelToken? cancelToken,
  }) async {
    final response = await HttpUtil.dio.get(
      '${Constants.baseUrl}${ApiPath.replySupport}',
      queryParameters: {'commentid': commentId, 'id': id},
      cancelToken: cancelToken,
    );
    return response.data.toString();
  }
}
