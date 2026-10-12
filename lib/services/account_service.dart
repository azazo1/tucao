import 'package:get/get.dart';
import 'package:tucao/models/form_response.dart';
import 'package:tucao/models/user.dart';
import 'package:tucao/http/init.dart';
import 'package:tucao/http/user_http.dart';
import 'package:tucao/utils/logger.dart';
import 'package:tucao/utils/storage.dart';

/// 账户状态.
///
/// 站点通过 cookie 维持登录态, 这里把登录用户信息缓存到本地,
/// 应用启动时再向服务端确认一次.
class AccountService extends GetxController {
  static AccountService get instance => Get.find<AccountService>();

  static const _kUser = 'user';

  final user = Rxn<UserModel>();
  int _sessionVersion = 0;

  bool get isLogin => user.value != null;

  @override
  void onInit() {
    super.onInit();
    _loadCache();
    refresh();
  }

  void _loadCache() {
    final raw = GStorage.account.get(_kUser);
    if (raw is Map) {
      user.value = UserModel.fromJson(raw.cast<String, dynamic>());
      Log.i('读取本地登录信息: ${user.value?.displayName}');
    }
  }

  /// 向服务端确认登录状态.
  @override
  Future<void> refresh() async {
    final sessionVersion = _sessionVersion;
    try {
      final info = await UserHttp.info();
      if (sessionVersion != _sessionVersion) {
        return;
      }
      if (info == null) {
        await _clear();
        return;
      }
      user.value = info;
      await GStorage.account.put(_kUser, info.toJson());
      Log.i('登录状态确认成功: ${info.displayName}');
    } catch (e, stackTrace) {
      Log.e('查询登录状态失败', error: e, stackTrace: stackTrace);
    }
  }

  /// 登录.
  Future<String> login(String username, String password) async {
    final sessionVersion = ++_sessionVersion;
    final raw = await UserHttp.login(username: username, password: password);
    // discuz 登录失败时返回带提示的页面, 成功时通常是跳转脚本.
    if (raw.contains('密码错误') || raw.contains('登录失败') || raw.contains('不存在')) {
      throw Exception('用户名或密码错误');
    }
    await _confirmLogin(
      failure: '登录失败, 请检查用户名与密码',
      sessionVersion: sessionVersion,
    );
    return raw;
  }

  /// 注册.
  ///
  /// 站点注册失败时返回带提示的页面, 成功时通常是跳转脚本并直接登录.
  Future<String> register({
    required String username,
    required String nickname,
    required String email,
    required String password,
    required String confirmPassword,
  }) async {
    final sessionVersion = ++_sessionVersion;
    final raw = await UserHttp.register(
      username: username,
      nickname: nickname,
      email: email,
      password: password,
      confirmPassword: confirmPassword,
    );
    final failure = registerFailure(raw);
    if (failure != null) {
      throw Exception(failure);
    }
    await _confirmLogin(
      failure: '注册成功但自动登录失败, 请手动登录',
      sessionVersion: sessionVersion,
    );
    return raw;
  }

  /// 登录操作必须用本次服务端查询确认, 不能沿用刷新失败后保留的缓存.
  Future<void> _confirmLogin({
    required String failure,
    required int sessionVersion,
  }) async {
    final info = await UserHttp.info();
    if (sessionVersion != _sessionVersion) {
      throw Exception('账号状态已变化, 请重新操作');
    }
    if (info == null || info.userId <= 0 || info.userName.isEmpty) {
      await _clear();
      throw Exception(failure);
    }
    user.value = info;
    await GStorage.account.put(_kUser, info.toJson());
    Log.i('登录状态确认成功: ${info.displayName}');
  }

  /// 修改密码.
  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
    required String confirmPassword,
  }) async {
    final raw = await UserHttp.changePassword(
      oldPassword: oldPassword,
      newPassword: newPassword,
      confirmPassword: confirmPassword,
    );
    final failure = formFailure(raw, fallback: '修改密码失败, 请检查填写的信息');
    if (failure != null) {
      throw Exception(failure);
    }
    // 与官方客户端一致, 密码修改后本地用户失效, 不假定服务器撤销了会话.
    _sessionVersion++;
    await _clear();
    await HttpInit.clearCookie();
  }

  /// 从表单提示页提取失败原因, 仅明确成功时返回 null.
  static String? formFailure(String raw, {required String fallback}) {
    // 脚本里的 showmessage 只作为错误提示, 不能作为成功凭据.
    final match = RegExp(r"showmessage\('([^']+)'").firstMatch(raw);
    final message = match?.group(1)?.trim();
    if (message != null && message.isNotEmpty) {
      return message;
    }
    final response = FormResponse.parse(raw);
    if (response.isSuccess) {
      return null;
    }
    if (response.status == FormResponseStatus.rejected) {
      return response.message;
    }
    return fallback;
  }

  /// 注册响应的失败原因, 保留旧名字以便测试与调用方使用.
  static String? registerFailure(String raw) =>
      formFailure(raw, fallback: '注册失败, 请检查填写的信息');

  /// 退出登录.
  Future<void> logout() async {
    _sessionVersion++;
    try {
      await UserHttp.logout();
    } catch (e, stackTrace) {
      Log.e('退出登录请求失败', error: e, stackTrace: stackTrace);
    }
    await HttpInit.clearCookie();
    await _clear();
  }

  Future<void> _clear() async {
    user.value = null;
    await GStorage.account.delete(_kUser);
  }
}
