import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:tucao/common/constants.dart';
import 'package:tucao/http/api_path.dart';
import 'package:tucao/models/message.dart';
import 'package:tucao/utils/http_util.dart';
import 'package:tucao/utils/logger.dart';

/// 私信数据源.
///
/// 站点是 discuz 的消息模块, 只提供 html, 需要登录态.
/// 页面结构沿用官方客户端的解析方式:
/// - 收件箱是 `div.minbox div.item`, 头像在 `div.l img`, 链接带 `messageid=数字`,
///   对方昵称在 `div.u`, 摘要在 `div.c`, 时间在 `div.t`.
/// - 详情是 `div.mread > div.item`, 头像链接指向 `/play/u{uid}/`,
///   与自己 uid 相同的条目即为本人发出.
abstract final class MessageHttp {
  static Future<List<MessageModel>> inbox({
    CancelToken? cancelToken,
  }) async {
    final response = await HttpUtil.dio.get(
      '${Constants.baseUrl}${ApiPath.messageList}',
      options: Options(headers: {'user-agent': Constants.desktopUserAgent}),
      cancelToken: cancelToken,
    );
    final list = parseInboxHtml(response.data.toString());
    Log.i('收件箱解析完成, 共 ${list.length} 条');
    return list;
  }

  static Future<List<MessageDetail>> detail({
    required String messageId,
    required String selfUid,
    CancelToken? cancelToken,
  }) async {
    final response = await HttpUtil.dio.get(
      '${Constants.baseUrl}${ApiPath.messageDetail}',
      queryParameters: {'messageid': messageId},
      options: Options(headers: {'user-agent': Constants.desktopUserAgent}),
      cancelToken: cancelToken,
    );
    final list = parseDetailHtml(response.data.toString(), selfUid);
    Log.i('私信详情解析完成, 共 ${list.length} 条');
    return list;
  }

  /// 发送私信, 成功返回空, 失败返回提示文本.
  static Future<String?> send({
    required String toUser,
    required String subject,
    required String content,
    CancelToken? cancelToken,
  }) async {
    final raw = await _post(ApiPath.messageSend, {
      'info[send_to_id]': toUser,
      'info[subject]': subject,
      'info[content]': content,
      'dosubmit': '1',
    }, cancelToken);
    return _parseResult(raw);
  }

  /// 回复私信, 成功返回空, 失败返回提示文本.
  static Future<String?> reply({
    required String replyId,
    required String toUserId,
    required String subject,
    required String content,
    CancelToken? cancelToken,
  }) async {
    final raw = await _post(ApiPath.messageReply, {
      'info[content]': content,
      'info[replyid]': replyId,
      'info[send_to_id]': toUserId,
      'info[subject]': subject,
      'dosubmit': '1',
    }, cancelToken);
    return _parseResult(raw);
  }

  static Future<String> _post(
    String path,
    Map<String, String> data,
    CancelToken? cancelToken,
  ) async {
    final response = await HttpUtil.dio.post(
      '${Constants.baseUrl}$path',
      data: data,
      options: Options(contentType: Headers.formUrlEncodedContentType),
      cancelToken: cancelToken,
    );
    return response.data.toString();
  }

  /// 站点成功时返回 1, 失败时返回提示文本.
  static String? _parseResult(String raw) {
    final text = raw.replaceAll(RegExp(r'<[^>]*>'), '').trim();
    if (text.isEmpty || text == '1' || text.contains('成功')) {
      return null;
    }
    if (text.contains('登录') || text.contains('登陆')) {
      return '请先登录后再操作';
    }
    Log.w('私信接口返回: $text');
    return text.length > 40 ? '操作失败' : text;
  }

  /// 解析收件箱页面.
  ///
  /// 昵称, 摘要与时间都是相对标题链接查找的兄弟节点, 与官方客户端一致,
  /// 不直接在整个 item 里找, 避免 item 内还有别的同类节点时取错.
  static List<MessageModel> parseInboxHtml(String raw) {
    final document = html_parser.parse(raw);
    final list = <MessageModel>[];
    final seen = <String>{};

    for (final item in document.querySelectorAll('div.minbox div.item')) {
      final link = item.querySelector('div.r a[href*=messageid]');
      final id = _parseMessageId(link?.attributes['href'] ?? '');
      if (id == null || !seen.add(id)) {
        continue;
      }
      list.add(
        MessageModel(
          id: id,
          username: link?.querySelector('div.u')?.text.trim() ??
              item.querySelector('div.u')?.text.trim() ??
              '',
          avatar: item.querySelector('div.l img')?.attributes['src'] ?? '',
          time: link?.querySelector('div.t')?.text.trim() ??
              item.querySelector('div.t')?.text.trim() ??
              '',
          message: link?.querySelector('div.c')?.text.trim() ??
              item.querySelector('div.c')?.text.trim() ??
              '',
        ),
      );
    }
    return list;
  }

  /// 解析私信详情页面.
  ///
  /// [selfUid] 是当前登录用户的 uid, 用来判断每条消息是否自己发出.
  static List<MessageDetail> parseDetailHtml(String raw, String selfUid) {
    final document = html_parser.parse(raw);
    final list = <MessageDetail>[];
    for (final item in document.querySelectorAll('div.mread > div.item')) {
      final href = item.querySelector('div.l a')?.attributes['href'] ?? '';
      final uid = _parseUid(href);
      final isMine = uid != null && uid == selfUid;
      list.add(
        MessageDetail(
          content: item.querySelector('div.r div.c')?.text.trim() ?? '',
          time: item.querySelector('div.r div.t')?.text.trim() ?? '',
          isMine: isMine,
          avatar: item.querySelector('div.l img')?.attributes['src'] ?? '',
          userId: uid ?? '',
        ),
      );
    }
    return list;
  }

  static String? _parseMessageId(String href) {
    final match = RegExp(r'messageid=(\d+)').firstMatch(href);
    return match?.group(1);
  }

  static String? _parseUid(String href) {
    final match = RegExp(r'/play/u(\d+)/').firstMatch(href);
    return match?.group(1);
  }
}
