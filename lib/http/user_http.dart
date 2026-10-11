import 'package:dio/dio.dart';
import 'package:tucao/common/constants.dart';
import 'package:tucao/http/api_path.dart';
import 'package:tucao/models/user.dart';
import 'package:tucao/utils/http_util.dart';

/// 用户相关接口.
abstract final class UserHttp {
  /// 查询当前登录状态.
  ///
  /// 未登录时接口返回 `{"islogin":false}`.
  static Future<UserModel?> info({CancelToken? cancelToken}) async {
    final response = await HttpUtil.dio.get(
      '${Constants.baseUrl}${ApiPath.userInfo}',
      cancelToken: cancelToken,
    );
    final raw = response.data.toString().replaceFirst('\ufeff', '').trim();
    if (raw.isEmpty) {
      return null;
    }
    final json = HttpUtil.decodeJson(raw);
    if (json['islogin'] == false) {
      return null;
    }
    // 接口在不同登录状态下返回的字段层级不一致, 逐层向下找.
    final data = json['data'] ?? json['result'] ?? json;
    if (data is Map) {
      final map = data.cast<String, dynamic>();
      if (map['userid'] == null && map['uid'] == null) {
        for (final value in map.values) {
          if (value is Map && (value['userid'] != null || value['uid'] != null)) {
            return UserModel.fromJson(value.cast<String, dynamic>());
          }
        }
      }
      return UserModel.fromJson(map);
    }
    return null;
  }

  /// 登录.
  ///
  /// 站点是 discuz 表单登录, 成功后由 cookie 维持会话.
  static Future<String> login({
    required String username,
    required String password,
    String? questionId,
    String? answer,
    CancelToken? cancelToken,
  }) async {
    final response = await HttpUtil.dio.post(
      '${Constants.baseUrl}${ApiPath.login}',
      data: {
        'username': username,
        'password': password,
        'questionid': ?questionId,
        'answer': ?answer,
        'cookietime': '2592000',
      },
      options: Options(contentType: Headers.formUrlEncodedContentType),
      cancelToken: cancelToken,
    );
    return response.data.toString();
  }

  /// 退出登录.
  static Future<void> logout({CancelToken? cancelToken}) async {
    await HttpUtil.dio.get(
      '${Constants.baseUrl}${ApiPath.logout}',
      cancelToken: cancelToken,
    );
  }

  /// 注册.
  ///
  /// 字段与站点注册表单一致, 成功时站点返回跳转脚本, 失败时返回带提示的页面.
  static Future<String> register({
    required String username,
    required String nickname,
    required String email,
    required String password,
    required String confirmPassword,
    CancelToken? cancelToken,
  }) async {
    final response = await HttpUtil.dio.post(
      '${Constants.baseUrl}${ApiPath.register}',
      data: {
        'username': username,
        'nickname': nickname,
        'email': email,
        'password': password,
        'pwdconfirm': confirmPassword,
        'dosubmit': '1',
      },
      options: Options(contentType: Headers.formUrlEncodedContentType),
      cancelToken: cancelToken,
    );
    return response.data.toString();
  }

  /// 修改密码.
  ///
  /// 字段名与官方 changePassword 一致, 需要登录态.
  static Future<String> changePassword({
    required String oldPassword,
    required String newPassword,
    required String confirmPassword,
    CancelToken? cancelToken,
  }) async {
    final response = await HttpUtil.dio.post(
      '${Constants.baseUrl}${ApiPath.changePassword}',
      data: {
        'info[password]': oldPassword,
        'info[newpassword]': newPassword,
        'info[renewpassword]': confirmPassword,
        'dosubmit': '1',
      },
      options: Options(contentType: Headers.formUrlEncodedContentType),
      cancelToken: cancelToken,
    );
    return response.data.toString();
  }
}
