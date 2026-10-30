import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tucao/utils/logger.dart';

/// 复制文本到剪贴板, 并给出统一的提示.
///
/// 传入的文本会去掉首尾空白, 正文内部的换行保持不变.
Future<void> copyText(BuildContext context, String text) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final content = text.trim();
  if (content.isEmpty) {
    messenger?.showSnackBar(
      const SnackBar(content: Text('没有可复制的内容'), duration: Duration(seconds: 2)),
    );
    return;
  }
  try {
    await Clipboard.setData(ClipboardData(text: content));
    messenger?.showSnackBar(
      const SnackBar(content: Text('已复制'), duration: Duration(seconds: 2)),
    );
  } catch (error, stackTrace) {
    Log.e('复制文本失败', error: error, stackTrace: stackTrace);
    messenger?.showSnackBar(
      const SnackBar(
        content: Text('复制失败, 请重试'),
        duration: Duration(seconds: 2),
      ),
    );
  }
}
