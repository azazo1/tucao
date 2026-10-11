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
