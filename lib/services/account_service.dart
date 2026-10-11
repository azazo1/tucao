import 'package:get/get.dart';
import 'package:tucao/models/reply.dart';
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
