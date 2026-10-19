import 'dart:async';

import 'package:flutter/widgets.dart';
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
class MessageCountService extends GetxController with WidgetsBindingObserver {
  static MessageCountService get instance => Get.find<MessageCountService>();

  /// 定时取数的间隔.
  ///
  /// 站点没有推送, 数字只能自己取: 间隔太短平白多出请求, 太长则角标明显
  /// 落后. 应用退到后台时这个定时器会停掉, 回前台时立刻取一次再继续.
  static const pollInterval = Duration(minutes: 5);

  /// 自动取数之间的最小间隔.
  ///
  /// 启动, 回到前台与定时轮询可能撞在一起, 这里挡掉短时间内重复的自动取数;
  /// 下拉刷新与从消息页返回是手动路径, 不受它影响.
  static const _autoThrottle = Duration(seconds: 30);

  /// 收件箱未读数.
  final inbox = 0.obs;

  /// 评论未读数.
  final comment = 0.obs;

  /// 两处之和, 底部入口的红色数字用它.
  int get total => inbox.value + comment.value;

  /// 是否正在取数, 连续触发时只跑一次.
  bool _loading = false;

  /// 上次取数的时间, 供自动触发的节流使用.
  DateTime? _lastLoad;

  /// 定时取数, 只在前台跑.
  Timer? _timer;

  Worker? _userWorker;

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
    _startPolling();
    // 换号或退出登录后旧数字不再是本次账号的状态, 重新取一次.
    _userWorker = ever<UserModel?>(AccountService.instance.user, (user) {
      if (user == null) {
        clear();
        return;
      }
      unawaited(reload());
    });
  }

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopPolling();
    _userWorker?.dispose();
    super.onClose();
  }

  /// 回到前台时立刻取一次并恢复定时取数, 退到后台则停掉定时器.
  ///
  /// 后台里定时器起不到提示作用, 还可能被系统限制, 干脆停了; 短暂失焦
  /// (切到别的应用又切回来前的那一下) 不改动定时器, 免得反复开关.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startPolling();
      unawaited(reload(auto: true));
      return;
    }
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _stopPolling();
    }
  }

  void _startPolling() {
    _timer ??= Timer.periodic(
      pollInterval,
      (_) => unawaited(reload(auto: true)),
    );
  }

  void _stopPolling() {
    _timer?.cancel();
    _timer = null;
  }

  /// 重新取一次未读数.
  ///
  /// [auto] 为真表示由定时或生命周期自动触发, 会被 [_autoThrottle] 节流;
  /// 下拉刷新与从消息页返回走手动路径, 每次都真的去取.
  Future<void> reload({bool auto = false}) async {
    if (_loading) {
      return;
    }
    final now = DateTime.now();
    final last = _lastLoad;
    if (auto && last != null && now.difference(last) < _autoThrottle) {
      return;
    }
    _lastLoad = now;
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
