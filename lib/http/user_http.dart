import 'package:dio/dio.dart';
import 'package:tucao/common/constants.dart';
import 'package:tucao/http/api_path.dart';
import 'package:tucao/models/form_response.dart';
import 'package:tucao/models/user.dart';
import 'package:tucao/utils/http_util.dart';

/// 用户相关接口.
abstract final class UserHttp {
  static bool _isSuccessStatus(int? status) =>
      status != null && status >= 200 && status < 300;

  /// 查询当前登录状态.
  ///
  /// 未登录时接口返回 `{"islogin":false}`.
  static Future<UserModel?> info({CancelToken? cancelToken}) async {
    final response = await HttpUtil.dio.get(
      '${Constants.baseUrl}${ApiPath.userInfo}',
      options: Options(validateStatus: _isSuccessStatus),
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
          if (value is Map &&
              (value['userid'] != null || value['uid'] != null)) {
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
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        validateStatus: _isSuccessStatus,
      ),
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
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        validateStatus: _isSuccessStatus,
      ),
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
        'dosubmit': '提交',
      },
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        validateStatus: _isSuccessStatus,
      ),
      cancelToken: cancelToken,
    );
    return response.data.toString();
  }

  /// 找回密码.
  ///
  /// 表单只有邮箱与验证码两项, 站点把新密码发到邮箱.
  /// 验证码与提交必须共用同一份 cookie, 否则站点判为验证码错误.
  static Future<FormResponse> forgotPassword({
    required String email,
    required String code,
    CancelToken? cancelToken,
  }) async {
    final response = await HttpUtil.dio.post(
      '${Constants.baseUrl}${ApiPath.forgotPassword}',
      data: {'email': email, 'code': code, 'dosubmit': '提交'},
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        validateStatus: (status) =>
            status != null && status >= 200 && status < 300,
      ),
      cancelToken: cancelToken,
    );
    return FormResponse.parse(response.data?.toString() ?? '');
  }

  /// 拉取图形验证码图片.
  ///
  /// 站点按 cookie 里的会话生成验证码, 因此这里必须走同一个 dio 实例.
  static Future<List<int>> checkCode({CancelToken? cancelToken}) async {
    final response = await HttpUtil.dio.get<List<int>>(
      '${Constants.baseUrl}${ApiPath.checkCode}',
      queryParameters: {'_': DateTime.now().microsecondsSinceEpoch},
      options: Options(
        responseType: ResponseType.bytes,
        headers: {'cache-control': 'no-cache'},
        validateStatus: (status) =>
            status != null && status >= 200 && status < 300,
      ),
      cancelToken: cancelToken,
    );
    final bytes = response.data;
    if (bytes == null ||
        bytes.isEmpty ||
        !(response.headers
                .value(Headers.contentTypeHeader)
                ?.toLowerCase()
                .startsWith('image/') ??
            false)) {
      throw const FormatException('站点未返回有效的验证码图片');
    }
    return bytes;
  }
}
