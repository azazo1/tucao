/// 登录用户信息.
class UserModel {
  const UserModel({
    required this.userId,
    required this.userName,
    this.avatar = '',
    this.nickname = '',
    this.groupName = '',
    this.credit = 0,
  });

  final int userId;
  final String userName;
  final String avatar;
  final String nickname;
  final String groupName;
  final int credit;

  String get displayName => nickname.isNotEmpty ? nickname : userName;

  factory UserModel.fromJson(Map<String, dynamic> json) => UserModel(
    userId: int.tryParse(
          (json['userid'] ?? json['uid'] ?? json['user_id'])?.toString() ?? '',
        ) ??
        0,
    userName:
        (json['username'] ?? json['name'] ?? json['user_name'])?.toString() ??
        '',
    avatar: (json['avatar'] ?? json['face'])?.toString() ?? '',
    nickname: (json['nickname'] ?? json['nick_name'])?.toString() ?? '',
    groupName: json['groupname']?.toString() ?? '',
    credit: int.tryParse(json['credit']?.toString() ?? '') ?? 0,
  );

  Map<String, dynamic> toJson() => {
    'userid': userId,
    'username': userName,
    'avatar': avatar,
    'nickname': nickname,
    'groupname': groupName,
    'credit': credit,
  };
}
