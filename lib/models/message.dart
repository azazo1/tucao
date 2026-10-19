/// 收件箱里的一条私信.
///
/// 字段与官方客户端的消息模型一致.
class MessageModel {
  const MessageModel({
    required this.id,
    required this.username,
    this.avatar = '',
    this.time = '',
    this.message = '',
  });

  /// 消息 id, 用于拉取详情与回复.
  final String id;

  /// 对方的昵称.
  final String username;

  final String avatar;

  /// 站点给出的时间文案.
  final String time;

  /// 消息摘要.
  final String message;
}

/// 私信详情里的一条消息.
///
/// 同一个会话里双方的消息都在这一个列表里, 用 [isMine] 区分左右.
class MessageDetail {
  const MessageDetail({
    required this.content,
    required this.time,
    required this.isMine,
    this.avatar = '',
    this.userId = '',
  });

  final String content;
  final String time;

  /// 是否是自己发出的.
  final bool isMine;

  final String avatar;

  /// 发送者的 uid, 回复时需要用对方的 uid 作为收件人.
  final String userId;
}

/// 系统公告列表里的一条.
///
/// 站点把公告放到消息模块的 group 动作下, 编号是 group_id, 发送者固定是
/// SYSTEM. 列表里没有单独的标题节点, 站点把标题写在摘要的第一行, 这里拆成
/// [title] 与 [summary].
class SystemMessage {
  const SystemMessage({
    required this.id,
    this.title = '',
    this.summary = '',
    this.time = '',
    this.avatar = '',
    this.unread = false,
  });

  /// 公告编号, 用于拉取详情.
  final String id;

  /// 标题, 取摘要的第一行.
  final String title;

  /// 标题之外的摘要文字, 已经折成一行.
  final String summary;

  final String time;

  final String avatar;

  /// 站点条目里是否带未读标记, 打开详情后站点自己会清掉.
  final bool unread;
}

/// 系统公告详情.
class SystemMessageDetail {
  const SystemMessageDetail({
    this.title = '',
    this.time = '',
    this.blocks = const [],
  });

  final String title;

  final String time;

  /// 正文分块, 按页面顺序排列, 交给界面用原生组件渲染.
  final List<SystemContentBlock> blocks;
}

/// 公告正文里的一块内容.
sealed class SystemContentBlock {
  const SystemContentBlock();
}

/// 一个段落, 段落内的文字与链接按顺序排列.
class SystemParagraph extends SystemContentBlock {
  const SystemParagraph(this.parts);

  final List<SystemTextPart> parts;
}

/// 段落里的一段文字, [url] 非空时是链接.
class SystemTextPart {
  const SystemTextPart(this.text, {this.url});

  final String text;

  final String? url;
}

/// 独立成块的图片, [url] 已经补成绝对地址.
class SystemImage extends SystemContentBlock {
  const SystemImage(this.url);

  final String url;
}

/// 评论列表里的一条, 对应自己在站点发表的评论.
///
/// 站点把这条记录放在会员中心的 comment 动作下, 除了评论正文, 还带着被
/// 评论内容的封面, 分区, 标题, 作者与时间, 方便点回原内容.
class CommentMessage {
  const CommentMessage({
    required this.title,
    required this.content,
    this.cover = '',
    this.url = '',
    this.category = '',
    this.author = '',
    this.authorUrl = '',
    this.time = '',
  });

  /// 被评论内容的标题.
  final String title;

  /// 评论正文.
  final String content;

  /// 被评论内容的封面, 已补成绝对地址.
  final String cover;

  /// 被评论内容的站内地址, 已补成绝对地址.
  final String url;

  /// 被评论内容所在分区, 如 档案.
  final String category;

  /// 被评论内容的作者昵称.
  final String author;

  /// 作者空间地址, 已补成绝对地址.
  final String authorUrl;

  /// 评论时间, 站点在列表里只给到日期.
  final String time;

  /// 评论指向的内容, 地址解析不出来时为 null.
  CommentTarget? get target => CommentTarget.parse(url);

  /// 作者 uid, 取不到时为空.
  String get authorId {
    final match = RegExp(r'/play/u(\d+)/').firstMatch(authorUrl);
    return match?.group(1) ?? '';
  }
}

/// 评论指向的内容.
///
/// 站点用路径前缀区分内容模型: 档案是 `play/d{hid}/`, 视频是 `play/h{hid}/`.
class CommentTarget {
  const CommentTarget({required this.hid, required this.article});

  final String hid;

  /// 是否是档案内容.
  final bool article;

  /// 从站内地址解析目标, 不是内容页时返回 null.
  static CommentTarget? parse(String url) {
    final match = RegExp(r'/play/([hd])(\d+)/').firstMatch(url);
    if (match == null) {
      return null;
    }
    return CommentTarget(
      hid: match.group(2) ?? '',
      article: match.group(1) == 'd',
    );
  }
}

/// 评论列表的一页.
class CommentMessagePage {
  const CommentMessagePage({this.list = const [], this.hasMore = false});

  final List<CommentMessage> list;

  /// 页面里是否还有下一页.
  final bool hasMore;
}
