import 'package:tucao/common/vip.dart';
import 'package:tucao/utils/site_url.dart';

/// 评论条目.
class ReplyModel {
  const ReplyModel({
    required this.id,
    required this.commentId,
    required this.userId,
    required this.userName,
    required this.content,
    this.avatar = '',
    this.createAt = '',
    this.support = 0,
    this.replyCount = 0,
    this.replyId = 0,
    this.replyUserId = 0,
    this.replyUserName = '',
    this.isVip = false,
    this.replies = const [],
  });

  final String id;

  /// 评论所属的楼, 形如 `content_11-4107860-1`.
  final String commentId;

  final int userId;
  final String userName;
  final String content;
  final String avatar;

  /// 服务器返回的格式化时间字符串.
  final String createAt;

  /// 点赞数.
  final int support;

  /// 子评论数量.
  final int replyCount;

  /// 被回复的评论 id, 为 0 表示一级评论.
  final int replyId;

  final int replyUserId;
  final String replyUserName;

  /// 评论者是否是站点破会员.
  ///
  /// 只有站点把整条用户记录塞进 `nickname` 时才有值 (评论者没设昵称的情况),
  /// 其它评论者的会员标记由评论页的昵称颜色补齐, 见 `VipService`.
  final bool isVip;

  /// 楼中楼回复, 仅在展开时填充.
  final List<ReplyModel> replies;

  bool get isRoot => replyId == 0;

  factory ReplyModel.fromJson(Map<String, dynamic> json) {
    final rawReplies = json['replies'];
    // 站点在评论者没有设置昵称时会把整条用户记录写进 nickname,
    // 直接取字符串会得到一长串 map 文本, 因此这里单独处理.
    final rawNickname = json['nickname'];
    final user = rawNickname is Map
        ? rawNickname.cast<String, dynamic>()
        : const <String, dynamic>{};
    final nickname = user.isNotEmpty
        ? _nameOfUser(user)
        : rawNickname?.toString().trim() ?? '';
    return ReplyModel(
      id: json['id']?.toString() ?? '',
      commentId: json['commentid']?.toString() ?? '',
      userId: int.tryParse(json['userid']?.toString() ?? '') ?? 0,
      userName: nickname.isNotEmpty
          ? nickname
          : json['username']?.toString() ?? '',
      content: json['content']?.toString() ?? '',
      avatar: avatarUrl(json['avatar']?.toString() ?? ''),
      createAt: json['creat_at']?.toString() ?? '',
      support: int.tryParse(json['support']?.toString() ?? '') ?? 0,
      replyCount: int.tryParse(json['replys']?.toString() ?? '') ?? 0,
      replyId: int.tryParse(json['replyid']?.toString() ?? '') ?? 0,
      replyUserId: int.tryParse(json['replyuid']?.toString() ?? '') ?? 0,
      replyUserName: json['rusername']?.toString() ?? '',
      isVip: Vip.fromApiValue(user['vip']),
      replies: rawReplies is List
          ? rawReplies
                .whereType<Map>()
                .map((e) => ReplyModel.fromJson(e.cast<String, dynamic>()))
                .toList()
          : const [],
    );
  }

  /// 用户记录里的显示名: 昵称为空时退回用户名.
  static String _nameOfUser(Map<String, dynamic> user) {
    final nickname = user['nickname']?.toString().trim() ?? '';
    if (nickname.isNotEmpty) {
      return nickname;
    }
    return user['username']?.toString().trim() ?? '';
  }

  ReplyModel copyWith({List<ReplyModel>? replies}) => ReplyModel(
    id: id,
    commentId: commentId,
    userId: userId,
    userName: userName,
    content: content,
    avatar: avatar,
    createAt: createAt,
    support: support,
    replyCount: replyCount,
    replyId: replyId,
    replyUserId: replyUserId,
    replyUserName: replyUserName,
    isVip: isVip,
    replies: replies ?? this.replies,
  );
}

/// 评论分页结果.
class ReplyPage {
  const ReplyPage({
    required this.total,
    required this.list,
    this.title = '',
  });

  final int total;
  final List<ReplyModel> list;
  final String title;

  factory ReplyPage.fromJson(Map<String, dynamic> json) {
    final rawData = json['data'];
    final list = <ReplyModel>[];
    if (rawData is Map) {
      for (final value in rawData.values) {
        if (value is Map) {
          list.add(ReplyModel.fromJson(value.cast<String, dynamic>()));
        }
      }
    } else if (rawData is List) {
      for (final value in rawData) {
        if (value is Map) {
          list.add(ReplyModel.fromJson(value.cast<String, dynamic>()));
        }
      }
    }
    return ReplyPage(
      total: int.tryParse(json['total']?.toString() ?? '') ?? list.length,
      list: list,
      title: json['title']?.toString() ?? '',
    );
  }
}
