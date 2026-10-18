import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tucao/services/ad_service.dart';

/// 二次确认后关闭广告入口, 并退回主页面.
Future<void> confirmDisableAd(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('关闭广告入口'),
      content: const Text('关闭后首页标题栏不再显示广告按钮, 可在设置中重新开启.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('关闭'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) {
    return;
  }
  AdService.instance.setEnabled(false);
  Navigator.of(context).popUntil((route) => route.isFirst);
  Get.snackbar('已关闭广告入口', '可在设置中重新开启');
}
