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

  /// 评论总数.
  ///
  /// 只取一条评论, 页面用不到内容, 省流量.
  static Future<int> count({
    required int typeId,
    required String hid,
    CancelToken? cancelToken,
  }) async {
    final page = await list(
      typeId: typeId,
      hid: hid,
      pageSize: 1,
      cancelToken: cancelToken,
    );
    return page.total;
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

  /// 图评单张图片的字节上限, 与站点网页端一致.
  static const maxImageBytes = 2 * 1024 * 1024;

  /// 站点接受的图片后缀, 其余一律按 jpg 处理.
  static const _imageExtensions = {'jpg', 'jpeg', 'png', 'gif', 'webp'};

  /// 生成上传用的文件名.
  ///
  /// 只保留后缀, 其余部分换成 ASCII 与时间戳: 系统里的原名可能带中文或空白,
  /// 放进 multipart 头里容易被站点读成乱码, 站点存图也只需要后缀.
  static String uploadFileName(String raw) {
    final dot = raw.lastIndexOf('.');
    final ext = dot < 0 ? '' : raw.substring(dot + 1).toLowerCase();
    final suffix = _imageExtensions.contains(ext) ? ext : 'jpg';
    return 'tucao_${DateTime.now().millisecondsSinceEpoch}.$suffix';
  }

  /// 上传图评图片, 返回可直接插进评论正文的站点片段.
  ///
  /// 图评是破会员特权, 站点对非会员会直接拒收; 权限与大小的前置检查在
  /// `ReplyController.uploadImage` 里做, 这里只负责把字节送出去并解析结果.
  /// 站点返回的片段由站点自己渲染成评论里的图片, 客户端不要去拼格式.
  static Future<String> uploadImage({
    required int typeId,
    required String hid,
    required String fileName,
    required List<int> bytes,
    CancelToken? cancelToken,
  }) async {
    final response = await HttpUtil.dio.post(
      '${Constants.baseUrl}${ApiPath.replyUploadImage}',
      queryParameters: {'commentid': ApiPath.commentId(typeId, hid)},
      data: FormData.fromMap({
        'file': MultipartFile.fromBytes(
          bytes,
          filename: uploadFileName(fileName),
        ),
      }),
      // 站点网页端用 jQuery 提交, 服务端可能按这个头判断是不是 ajax 请求,
      // 补上与网页端一致的头, 免得被当成非法来源.
      options: Options(headers: {'X-Requested-With': 'XMLHttpRequest'}),
      cancelToken: cancelToken,
    );
    return parseUploadResponse(response.data.toString());
  }

  /// 解析上传接口的返回.
  ///
  /// 成功是 `{"status":1,"bbcode":"..."}`, 失败是 `{"status":0,"msg":"..."}`.
  /// 站点有时把 status 写成字符串, 这里统一按数字比较. 会话过期时返回的是
  /// 一整页 html, 按 json 解析会抛出难以理解的错误, 这里先识别成登录失效.
  static String parseUploadResponse(String raw) {
    final text = raw.replaceFirst('\ufeff', '').trim();
    if (text.contains('会话已过期') ||
        text.contains('请先登录') ||
        text.contains('您需要登录')) {
      throw Exception('登录已失效, 请重新登录');
    }
    if (!text.startsWith('{')) {
      throw Exception('图片上传失败, 站点返回了无法识别的内容');
    }
    final json = HttpUtil.decodeJson(text);
    final status = int.tryParse(json['status']?.toString() ?? '') ?? 0;
    if (status == 1) {
      final snippet = json['bbcode']?.toString().trim() ?? '';
      if (snippet.isEmpty) {
        throw const FormatException('站点未返回图片地址');
      }
      return snippet;
    }
    final message = json['msg']?.toString().trim() ?? '';
    throw Exception(message.isEmpty ? '图片上传失败' : message);
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
