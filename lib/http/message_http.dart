import 'package:dio/dio.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:tucao/common/constants.dart';
import 'package:tucao/http/api_path.dart';
import 'package:tucao/models/message.dart';
import 'package:tucao/utils/http_util.dart';
import 'package:tucao/utils/logger.dart';
import 'package:tucao/utils/site_url.dart';

/// 私信, 评论与系统公告数据源.
///
/// 站点是 discuz 的消息模块, 只提供 html, 需要登录态. 私信收件箱是用户之间
/// 的会话, 系统公告是站点单方面发的通知, 两者页面结构相近但不是同一个动作,
/// 公告也没有回复入口. 评论列表在会员中心, 列出自己发表过的评论, 条目里带
/// 被评论内容的摘要, 用来跳回原内容.
///
/// 页面结构沿用官方客户端的解析方式:
/// - 收件箱是 `div.minbox div.item`, 头像在 `div.l img`, 链接带 `messageid=数字`,
///   对方昵称在 `div.u`, 摘要在 `div.c`, 时间在 `div.t`.
/// - 详情是 `div.mread > div.item`, 头像链接指向 `/play/u{uid}/`,
///   与自己 uid 相同的条目即为本人发出.
/// - 系统公告列表同样是 `div.minbox div.item`, 但链接带 `group_id=数字`,
///   未读的条目多一个 `span.tip`; 详情是 `div.group_show` 里的一段富文本.
/// - 评论列表是 `div.mcomment div.item`, 封面在 `div.l a img`, 分区在 `div.c`,
///   标题在 `div.t`, 作者与日期在 `div.tt`, 正文在 `div.d`.
/// 消息接口需要登录态, 站点认为没登录时抛出.
///
/// [toString] 直接给出可以显示的文案, 界面把异常文本原样当提示用.
class MessageLoginException implements Exception {
  const MessageLoginException();

  @override
  String toString() => '登录状态已过期, 请重新登录';
}

abstract final class MessageHttp {
  /// 消息页面的请求 UA.
  ///
  /// 站点把登录态和 UA 绑在一起校验, 登录用的是手机 UA. 换成桌面 UA 抓这些
  /// 页面会被判成未登录, 站点还会顺手让 cookie 失效, 用户那边的感受就是
  /// "打开私信就掉登录". 会员中心遇到过同样的问题, 见 LifeHttp, 站点侧的说明
  /// 记在 [Constants.desktopUserAgent] 上的 TOFIX(site).
  static const _pageUserAgent = Constants.userAgent;

  static Future<List<MessageModel>> inbox({
    CancelToken? cancelToken,
  }) async {
    final raw = await _fetchPage(
      ApiPath.messageList,
      container: 'div.minbox',
      cancelToken: cancelToken,
    );
    final list = parseInboxHtml(raw);
    Log.i('收件箱解析完成, 共 ${list.length} 条');
    return list;
  }

  static Future<List<MessageDetail>> detail({
    required String messageId,
    required String selfUid,
    CancelToken? cancelToken,
  }) async {
    final raw = await _fetchPage(
      ApiPath.messageDetail,
      query: {'messageid': messageId},
      container: 'div.mread',
      cancelToken: cancelToken,
    );
    final list = parseDetailHtml(raw, selfUid);
    Log.i('私信详情解析完成, 共 ${list.length} 条');
    return list;
  }

  /// 自己发表的评论.
  ///
  /// 与私信一样需要登录态, 页面按页返回, 是否还有下一页以页面里的分页链接
  /// 为准, 不按本页条数猜站点每页多少条.
  static Future<CommentMessagePage> comments({
    int page = 1,
    CancelToken? cancelToken,
  }) async {
    final raw = await _fetchPage(
      ApiPath.messageCommentList,
      query: {'page': page.toString()},
      container: 'div.mcomment',
      cancelToken: cancelToken,
    );
    final result = parseCommentListHtml(raw, page: page);
    Log.i('评论列表解析完成, 第 $page 页 ${result.list.length} 条');
    return result;
  }

  /// 系统公告列表.
  static Future<List<SystemMessage>> groupList({
    CancelToken? cancelToken,
  }) async {
    final raw = await _fetchPage(
      ApiPath.messageGroupList,
      container: 'div.minbox',
      cancelToken: cancelToken,
    );
    final list = parseGroupListHtml(raw);
    Log.i('系统公告解析完成, 共 ${list.length} 条');
    return list;
  }

  /// 系统公告详情.
  ///
  /// 站点在返回详情时就把这条公告标成已读, 应用不需要再调别的接口.
  static Future<SystemMessageDetail> groupDetail({
    required String groupId,
    CancelToken? cancelToken,
  }) async {
    final raw = await _fetchPage(
      ApiPath.messageGroupDetail,
      query: {'group_id': groupId},
      container: 'div.group_show',
      cancelToken: cancelToken,
    );
    return parseGroupDetailHtml(raw);
  }

  /// 抓一个需要登录态的消息页面.
  ///
  /// [container] 是这一页必须有的容器, 页面里没有它说明站点给的不是这个页面.
  static Future<String> _fetchPage(
    String path, {
    Map<String, String>? query,
    String? container,
    CancelToken? cancelToken,
  }) async {
    final response = await HttpUtil.dio.get(
      '${Constants.baseUrl}$path',
      queryParameters: query,
      options: Options(headers: {'user-agent': _pageUserAgent}),
      cancelToken: cancelToken,
    );
    final raw = response.data.toString();
    if (container != null &&
        html_parser.parse(raw).querySelector(container) == null &&
        _looksLikeLoginPage(raw)) {
      throw const MessageLoginException();
    }
    return raw;
  }

  /// 页面是不是在要求登录.
  ///
  /// 登录态失效时站点返回一个很短的提示页, 里面没有消息容器; 只有页面里出现
  /// 登录字样才当成登录失效, 免得站点改版时把别的页面误报成掉登录.
  static bool _looksLikeLoginPage(String raw) {
    final head = raw.length > 4096 ? raw.substring(0, 4096) : raw;
    return head.contains('登录') || head.contains('登陆');
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

  /// 解析系统公告列表.
  ///
  /// 条目结构与收件箱一致, 区别是链接带 `group_id`, 未读的条目多一个 tip.
  /// 站点不单独给标题节点, 标题写在摘要的第一行, 这里拆成标题与其余摘要.
  static List<SystemMessage> parseGroupListHtml(String raw) {
    final document = html_parser.parse(raw);
    final list = <SystemMessage>[];
    final seen = <String>{};

    for (final item in document.querySelectorAll('div.minbox div.item')) {
      final link = item.querySelector('div.r a[href*=group_id]');
      final id = _parseGroupId(link?.attributes['href'] ?? '');
      if (id == null || !seen.add(id)) {
        continue;
      }
      final lines = _splitLines(link?.querySelector('div.c')?.text ?? '');
      list.add(
        SystemMessage(
          id: id,
          title: lines.isEmpty ? '' : lines.first,
          summary: lines.skip(1).join(' '),
          time: _inlineText(link?.querySelector('div.t')?.text ?? ''),
          avatar: absoluteSiteUrl(
            item.querySelector('div.l img')?.attributes['src'] ?? '',
          ),
          unread: link?.querySelector('span.tip') != null,
        ),
      );
    }
    return list;
  }

  /// 解析系统公告详情.
  ///
  /// 公告正文是站点富文本, 这里按页面顺序拆成段落与图片, 交给界面用原生组件
  /// 渲染, 不把整页 html 塞进 WebView. 时间写在 "发表意见，2026-06-29 14:25:04"
  /// 这样一句话里, 从中取出日期部分.
  static SystemMessageDetail parseGroupDetailHtml(String raw) {
    final document = html_parser.parse(raw);
    final blocks = <SystemContentBlock>[];
    final body = document.querySelector('div.group_show');
    if (body != null) {
      // 站点在正文末尾放了一个清除浮动用的空块, 不属于正文.
      for (final clear in body.querySelectorAll('div.clear')) {
        clear.remove();
      }
      _collectBlocks(body, blocks);
    }
    final info = document.querySelector('div.group_info')?.text ?? '';
    final time = RegExp(
      r'\d{4}-\d{2}-\d{2}(?: \d{2}:\d{2}(?::\d{2})?)?',
    ).firstMatch(info);
    return SystemMessageDetail(
      title: _inlineText(document.querySelector('div.mnav_r a.t')?.text ?? ''),
      time: time?.group(0) ?? '',
      blocks: blocks,
    );
  }

  /// 解析评论列表.
  ///
  /// 条目结构: 封面在 `div.l a img`, 内容地址在 `div.l a`, 右侧依次是分区
  /// `div.c`, 标题 `div.t`, 作者与日期 `div.tt`, 评论正文 `div.d`. 站点在
  /// 分页区用 `下一页` 链接表示还有下一页, 这里按链接判断, 不猜每页条数.
  static CommentMessagePage parseCommentListHtml(
    String raw, {
    int page = 1,
  }) {
    final document = html_parser.parse(raw);
    final list = <CommentMessage>[];
    for (final item in document.querySelectorAll('div.mcomment div.item')) {
      final link =
          item.querySelector('div.l a') ??
          item.querySelector('div.r div.t a');
      final title = _inlineText(item.querySelector('div.r div.t')?.text ?? '');
      if (title.isEmpty) {
        continue;
      }
      final meta = item.querySelector('div.r div.tt');
      final authorLink = meta?.querySelector('a[href*=play/u]');
      list.add(
        CommentMessage(
          title: title,
          content: _inlineText(item.querySelector('div.r div.d')?.text ?? ''),
          cover: absoluteSiteUrl(
            item.querySelector('div.l img')?.attributes['src'] ?? '',
          ),
          url: absoluteSiteUrl(link?.attributes['href'] ?? ''),
          category: _inlineText(item.querySelector('div.r div.c')?.text ?? ''),
          author: _inlineText(authorLink?.text ?? ''),
          authorUrl: absoluteSiteUrl(authorLink?.attributes['href'] ?? ''),
          time: _dateText(meta?.text ?? ''),
        ),
      );
    }
    return CommentMessagePage(list: list, hasMore: _hasNextPage(document, page));
  }

  /// 从一句 `作者 · 2026-10-19` 里取出日期部分.
  static String _dateText(String raw) {
    final match = RegExp(
      r'\d{4}-\d{2}-\d{2}(?: \d{2}:\d{2}(?::\d{2})?)?',
    ).firstMatch(raw);
    return match?.group(0) ?? '';
  }

  /// 分页区里是否有比当前页更大的页码或下一页链接.
  static bool _hasNextPage(Document document, int page) {
    final pages = document.querySelector('div.pages');
    if (pages == null) {
      return false;
    }
    for (final link in pages.querySelectorAll('a')) {
      final text = _inlineText(link.text);
      if (text == '下一页' || text == '下页') {
        return true;
      }
      final match = RegExp(
        r'page=(\d+)',
      ).firstMatch(link.attributes['href'] ?? '');
      final number = int.tryParse(match?.group(1) ?? '');
      if (number != null && number > page) {
        return true;
      }
    }
    for (final span in pages.querySelectorAll('span')) {
      final number = int.tryParse(_inlineText(span.text));
      if (number != null && number > page) {
        return true;
      }
    }
    return false;
  }

  /// 正文里会断开段落的块级标签, 其余标签只当作行内元素继续往下走.
  static const _blockTags = {
    'p', 'div', 'li', 'ul', 'ol', 'dl', 'dd', 'dt', 'table', 'tr', 'td',
    'blockquote', 'pre', 'section', 'article', 'figure', 'figcaption',
    'h1', 'h2', 'h3', 'h4', 'h5', 'h6',
  };

  /// 把富文本正文按页面顺序拆成段落与图片.
  ///
  /// 站点给的正文只用到 p, a, img, br 这几种标签: 段落里的换行由 br 决定,
  /// 源码里的缩进与换行在浏览器里会被折成空格, 这里同样先折掉, 免得界面里
  /// 冒出一堆来历不明的换行.
  static void _collectBlocks(Element root, List<SystemContentBlock> out) {
    final parts = <SystemTextPart>[];
    final buffer = StringBuffer();

    void flushText() {
      final text = _blockText(buffer.toString());
      buffer.clear();
      if (text.isNotEmpty) {
        parts.add(SystemTextPart(text));
      }
    }

    void flushParagraph() {
      flushText();
      _trimEdges(parts);
      if (parts.isNotEmpty) {
        out.add(SystemParagraph(List<SystemTextPart>.unmodifiable(parts)));
        parts.clear();
      }
    }

    void addImage(Element image) {
      final url = absoluteSiteUrl(image.attributes['src'] ?? '');
      if (url.isEmpty) {
        return;
      }
      flushParagraph();
      out.add(SystemImage(url));
    }

    void walk(Node node) {
      for (final child in node.nodes) {
        if (child is Text) {
          buffer.write(child.text.replaceAll(RegExp(r'\s+'), ' '));
          continue;
        }
        if (child is! Element) {
          continue;
        }
        final tag = child.localName;
        if (tag == 'script' || tag == 'style') {
          continue;
        }
        if (tag == 'img') {
          addImage(child);
          continue;
        }
        if (tag == 'br') {
          buffer.write('\n');
          continue;
        }
        if (tag == 'a') {
          final text = _blockText(child.text);
          final images = child.querySelectorAll('img');
          // 站点会把宣传图整张贴成一个链接, 只有图片的链接按图片显示.
          if (text.trim().isNotEmpty) {
            flushText();
            final href = absoluteSiteUrl(child.attributes['href'] ?? '');
            parts.add(SystemTextPart(text, url: href.isEmpty ? null : href));
          }
          // 链接里同时有文字与图片时, 图片另起一块, 顺序与页面一致.
          for (final image in images) {
            addImage(image);
          }
          continue;
        }
        walk(child);
        if (_blockTags.contains(tag)) {
          flushParagraph();
        }
      }
    }

    walk(root);
    flushParagraph();
  }

  /// 去掉段落整体首尾的空白, 段落中间的空白保持原样.
  static void _trimEdges(List<SystemTextPart> parts) {
    if (parts.isNotEmpty) {
      final first = parts.first;
      final text = first.text.replaceFirst(RegExp(r'^\s+'), '');
      if (text.isEmpty) {
        parts.removeAt(0);
      } else {
        parts[0] = SystemTextPart(text, url: first.url);
      }
    }
    if (parts.isNotEmpty) {
      final last = parts.last;
      final text = last.text.replaceFirst(RegExp(r'\s+$'), '');
      if (text.isEmpty) {
        parts.removeLast();
      } else {
        parts[parts.length - 1] = SystemTextPart(text, url: last.url);
      }
    }
  }

  /// 单行文本: 空白折成一个空格并去掉首尾.
  static String _inlineText(String raw) =>
      raw.replaceAll(RegExp(r'\s+'), ' ').trim();

  /// 段落文本: 行内空白折成一个空格, 保留 br 换出来的换行.
  static String _blockText(String raw) => raw
      .replaceAll(RegExp(r'[ \t]+'), ' ')
      .replaceAll(RegExp(r' *\n *'), '\n')
      .replaceAll(RegExp(r'\n{2,}'), '\n');

  /// 把站点的多行文本拆成非空行.
  static List<String> _splitLines(String raw) => raw
      .split('\n')
      .map(_inlineText)
      .where((line) => line.isNotEmpty)
      .toList();

  static String? _parseGroupId(String href) {
    final match = RegExp(r'group_id=(\d+)').firstMatch(href);
    return match?.group(1);
  }

  static String? _parseUid(String href) {
    final match = RegExp(r'/play/u(\d+)/').firstMatch(href);
    return match?.group(1);
  }
}
