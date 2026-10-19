import 'dart:async';

import 'package:get/get.dart';
import 'package:tucao/http/message_http.dart';
import 'package:tucao/models/user.dart';
import 'package:tucao/services/account_service.dart';
import 'package:tucao/utils/logger.dart';

/// 未读消息计数.
///
/// 入口上的数字在列表之外也要看得到, 而列表只在对应页面打开时才请求, 因此
/// 这里单独维护一份, 由主框架与「我的」页决定何时刷新.
///
/// 数字直接取站点在会员中心导航里渲染的那两个, 不去碰评论页: 站点在打开
/// 评论页时就把评论未读清掉, 取数不该替用户看一遍列表.
///
/// 取数失败保留上一次的数字, 网络抖一下不至于让角标忽明忽暗.
class MessageCountService extends GetxController {
  /// 收件箱未读数.
  final inbox = 0.obs;

  /// 评论未读数.
  final comment = 0.obs;

  /// 两处之和, 底部入口的红色数字用它.
  int get total => inbox.value + comment.value;

  /// 是否正在取数, 连续触发时只跑一次.
  bool _loading = false;

  Worker? _userWorker;

  @override
  void onInit() {
    super.onInit();
    // 换号或退出登录后旧数字不再是本次账号的状态, 重新取一次.
    _userWorker = ever<UserModel?>(AccountService.instance.user, (user) {
      if (user == null) {
        clear();
        return;
      }
      unawaited(refresh());
    });
  }

  @override
  void onClose() {
    _userWorker?.dispose();
    super.onClose();
  }

  /// 重新取一次未读数.
  Future<void> refresh() async {
    if (_loading) {
      return;
    }
    _loading = true;
    try {
      if (!AccountService.instance.isLogin) {
        clear();
        return;
      }
      final counts = await MessageHttp.unreadCounts();
      inbox.value = counts.inbox;
      comment.value = counts.comment;
    } catch (e, stackTrace) {
      Log.e('读取未读数失败', error: e, stackTrace: stackTrace);
    } finally {
      _loading = false;
    }
  }

  /// 未登录与退出登录时把数字归零.
  void clear() {
    inbox.value = 0;
    comment.value = 0;
  }
}
