import 'package:tucao/common/vip.dart';

/// 登录用户信息.
class UserModel {
  const UserModel({
    required this.userId,
    required this.userName,
    this.avatar = '',
    this.nickname = '',
    this.groupName = '',
    this.credit = 0,
    this.isVip = false,
  });

  final int userId;
  final String userName;
  final String avatar;
  final String nickname;
  final String groupName;
  final int credit;

  /// 站点破会员.
  ///
  /// 取值来自 `api.php?op=user` 的 `vip` 字段, 该接口只返回当前登录用户,
  /// 因此这个标记只对本人有效, 判定规则见 [Vip.fromApiValue].
  final bool isVip;

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
    isVip: Vip.fromApiValue(json['vip']),
  );

  Map<String, dynamic> toJson() => {
    'userid': userId,
    'username': userName,
    'avatar': avatar,
    'nickname': nickname,
    'groupname': groupName,
    'credit': credit,
    // 本地缓存按接口的字符串写法回写, 重新解析时结果一致.
    'vip': isVip ? '1' : '0',
  };
}
