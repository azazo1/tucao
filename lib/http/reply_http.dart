import 'package:dio/dio.dart';
import 'package:tucao/common/constants.dart';
import 'package:tucao/http/api_path.dart';
import 'package:tucao/models/reply.dart';
import 'package:tucao/utils/http_util.dart';

/// 评论接口.
abstract final class ReplyHttp {
  /// 拉取评论.
  ///
  /// 参数与官方 reply 一致: commentid, replyid, page, num.
  /// [replyId] 不为空时拉取该评论下的楼中楼回复.
  static Future<ReplyPage> list({
    required int typeId,
    required String hid,
    int page = 1,
    int pageSize = 20,
    int? replyId,
    CancelToken? cancelToken,
  }) async {
    final response = await HttpUtil.dio.get(
      '${Constants.baseUrl}${ApiPath.replyList}',
      queryParameters: {
        'commentid': ApiPath.commentId(typeId, hid),
        'replyid': ?replyId,
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

  /// 发送评论或回复.
  ///
  /// 参数位置与官方 sendReply 一致: commentid, id 与 replyuid 是查询参数,
  /// 只有 content 是表单字段. [replyId] 为空表示发顶层评论,
  /// 不为空时 [replyUid] 必须是被回复者的 uid, 否则站点会拒收.
  static Future<String> send({
    required int typeId,
    required String hid,
    required String content,
    int? replyId,
    int? replyUid,
    CancelToken? cancelToken,
  }) async {
    final response = await HttpUtil.dio.post(
      '${Constants.baseUrl}${ApiPath.replySend}',
      queryParameters: {
        'commentid': ApiPath.commentId(typeId, hid),
        'id': ?replyId,
        'replyuid': ?replyUid,
      },
      data: {'content': content},
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
