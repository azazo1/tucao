import 'package:flutter/material.dart';
import 'package:tucao/utils/logger.dart';

/// 全局轻提示.
///
/// 应用里原先混用 GetX 顶部弹条与 Material 底部 SnackBar, 两种样式位置不同,
/// 顶部弹条还会挡住标题栏. 这里统一走根 ScaffoldMessenger 的底部浮动 SnackBar,
/// 样式由主题里的 snackBarTheme 决定. 用根 messenger 是因为不少地方先关页面再
/// 提示, 提示需要跟着留到下一页.
abstract final class Toast {
  /// 交给 GetMaterialApp 的 scaffoldMessengerKey.
  static final messengerKey = GlobalKey<ScaffoldMessengerState>();

  /// 显示一条提示, [detail] 为空时只有一行.
  ///
  /// 新提示直接顶掉旧的, 不排队, 连续操作时不会一条条慢慢放完.
  static void show(
    String title, {
    String? detail,
    Duration duration = const Duration(seconds: 3),
    SnackBarAction? action,
  }) {
    final messenger = messengerKey.currentState;
    if (messenger == null) {
      Log.w('提示未显示, 根 ScaffoldMessenger 还没挂载: $title');
      return;
    }
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: _content(title, detail),
          duration: duration,
          action: action,
        ),
      );
  }

  static Widget _content(String title, String? detail) {
    if (detail == null || detail.isEmpty) {
      return Text(title, maxLines: 2, overflow: TextOverflow.ellipsis);
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Text(detail, maxLines: 3, overflow: TextOverflow.ellipsis),
      ],
    );
  }
}
