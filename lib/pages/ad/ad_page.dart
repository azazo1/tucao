import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tucao/pages/ad/ad_actions.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// 应用内广告页.
///
/// 与官方客户端的 BrowserActivity 一致, 直接用应用内 WebView 打开推广页,
/// 不跳转外部浏览器; 需要系统应用处理的协议才交出去.
class AdPage extends StatefulWidget {
  const AdPage({super.key, required this.url});

  final String url;

  @override
  State<AdPage> createState() => _AdPageState();
}

class _AdPageState extends State<AdPage> {
  late final WebViewController _controller;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) {
              setState(() => _loading = true);
            }
          },
          onPageFinished: (_) {
            if (mounted) {
              setState(() => _loading = false);
            }
          },
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            if (uri == null) {
              return NavigationDecision.prevent;
            }
            if (uri.scheme == 'http' || uri.scheme == 'https') {
              return NavigationDecision.navigate;
            }
            // tmall:// 等协议交给系统, 避免 WebView 里报错.
            unawaited(
              launchUrl(
                uri,
                mode: LaunchMode.externalApplication,
              ).catchError((Object _) => false),
            );
            return NavigationDecision.prevent;
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  Future<void> _openInBrowser() async {
    try {
      final opened = await launchUrl(
        Uri.parse(widget.url),
        mode: LaunchMode.externalApplication,
      );
      if (!opened && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('无法打开浏览器')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('打开浏览器失败')));
      }
    }
  }

  Future<void> _handleBack() async {
    if (await _controller.canGoBack()) {
      await _controller.goBack();
      return;
    }
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  /// 关闭广告入口, 二次确认后立即退出广告页.
  Future<void> _cancelAd() => confirmDisableAd(context);

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          unawaited(_handleBack());
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('广告'),
          actions: [
            TextButton(
              onPressed: _cancelAd,
              child: const Text('取消广告'),
            ),
            IconButton(
              onPressed: _openInBrowser,
              tooltip: '在浏览器打开',
              icon: const Icon(Icons.open_in_browser),
            ),
          ],
        ),
        body: Stack(
          children: [
            WebViewWidget(controller: _controller),
            if (_loading)
              const LinearProgressIndicator(minHeight: 2),
          ],
        ),
      ),
    );
  }
}
