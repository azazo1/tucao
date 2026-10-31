import 'package:flutter/material.dart';
import 'package:tucao/utils/logger.dart';
import 'package:url_launcher/url_launcher.dart';

/// 用系统浏览器打开站点页面, 失败时给出统一提示.
Future<void> openInBrowser(BuildContext context, Uri uri) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    Log.i('在浏览器中打开: $uri');
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened) {
      Log.w('系统没有处理浏览器打开: $uri');
      messenger?.showSnackBar(
        const SnackBar(content: Text('无法打开浏览器, 可在菜单中复制链接')),
      );
    }
  } catch (error, stackTrace) {
    Log.e('在浏览器中打开失败', error: error, stackTrace: stackTrace);
    messenger?.showSnackBar(
      const SnackBar(content: Text('浏览器打开失败, 可在菜单中复制链接')),
    );
  }
}
