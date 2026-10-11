import 'package:get/get.dart';
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
    try {
      final info = await UserHttp.info();
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
    final raw = await UserHttp.login(username: username, password: password);
    // discuz 登录失败时返回带提示的页面, 成功时通常是跳转脚本.
    if (raw.contains('密码错误') ||
        raw.contains('登录失败') ||
        raw.contains('不存在')) {
      throw Exception('用户名或密码错误');
    }
    await refresh();
    if (!isLogin) {
      throw Exception('登录失败, 请检查用户名与密码');
    }
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
    await refresh();
    if (!isLogin) {
      throw Exception('注册成功但自动登录失败, 请手动登录');
    }
    return raw;
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
  }

  /// 从表单类接口的响应里提取失败原因, 成功时返回 null.
  ///
  /// 站点成功时返回的页面正文是 "操作成功" 加一段跳转脚本,
  /// 因此这里正向判断成功, 其余情况再尝试提取提示文案.
  /// 是纯函数, 便于用固定响应做测试.
  static String? formFailure(String raw, {required String fallback}) {
    final text = raw.replaceAll(RegExp(r'<[^>]*>'), ' ').trim();
    if (text.contains('操作成功')) {
      return null;
    }
    // 站点把提示放在脚本里, 形如 showmessage('...', ...).
    final match = RegExp(r"showmessage\('([^']+)'").firstMatch(raw);
    if (match != null) {
      final message = match.group(1)!.trim();
      if (message.isNotEmpty) {
        return message;
      }
    }
    for (final keyword in ['已存在', '已经被注册', '不正确', '不能为空', '失败', '过期']) {
      if (text.contains(keyword)) {
        return fallback;
      }
    }
    return null;
  }

  /// 注册响应的失败原因, 保留旧名字以便测试与调用方使用.
  static String? registerFailure(String raw) =>
      formFailure(raw, fallback: '注册失败, 请检查填写的信息');

  /// 退出登录.
  Future<void> logout() async {
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
