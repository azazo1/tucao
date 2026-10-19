import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:tucao/common/widgets/cc/cc_peek_thanks.dart';
import 'package:tucao/common/widgets/loading_widget.dart';
import 'package:tucao/http/ad_http.dart';
import 'package:tucao/pages/ad/ad_disclaimer.dart';
import 'package:tucao/pages/ad/ad_page.dart';
import 'package:tucao/services/account_service.dart';
import 'package:tucao/utils/logger.dart';

typedef AdLoader = Future<List<AdItem>> Function({CancelToken? cancelToken});
typedef AdReporter = Future<bool> Function(String adId);
typedef AdPageBuilder = Widget Function(AdItem ad);

Widget _buildAdPage(AdItem ad) => AdPage(url: ad.linkUrl);

/// 仅在非会员分支挂载, 避免感谢页仍在后台请求广告.
class AdFeed extends StatefulWidget {
  const AdFeed({
    super.key,
    required this.loadAds,
    this.reportClick = AdHttp.reportClick,
    this.buildAdPage = _buildAdPage,
  });

  final AdLoader loadAds;
  final AdReporter reportClick;
  final AdPageBuilder buildAdPage;

  @override
  State<AdFeed> createState() => _AdFeedState();
}

class _AdFeedState extends State<AdFeed> with WidgetsBindingObserver {
  late Future<List<AdItem>> _ads;
  CancelToken? _request;
  final _reported = <String>{};
  final _accepted = <String>{};
  bool _opening = false;
  bool _showThanks = false;
  bool _foreground = true;
  int _visit = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    _ads = _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 其他路由遮住列表时丢弃感谢, 不等下一次返回再补弹.
    if (ModalRoute.isCurrentOf(context) == false && !_opening) {
      _visit++;
      _showThanks = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) {
      // 看广告时去外部应用不算离开列表后的待展示窗口.
      if (!_opening) _visit++;
      _dismissThanks();
    }
    // resumed 从不创建感谢, 只能由广告路由 completed 之后创建.
  }

  Future<List<AdItem>> _load() {
    _request?.cancel('广告列表重新加载');
    final token = CancelToken();
    _request = token;
    return widget.loadAds(cancelToken: token);
  }

  @override
  void dispose() {
    _visit++;
    WidgetsBinding.instance.removeObserver(this);
    _request?.cancel('离开广告列表或会员状态变化');
    super.dispose();
  }

  void _reload() {
    _visit++;
    _reported.clear();
    _accepted.clear();
    setState(() {
      _showThanks = false;
      _ads = _load();
    });
  }

  void _dismissThanks() {
    if (mounted && _showThanks) setState(() => _showThanks = false);
  }

  Future<bool> _report(String adId) async {
    try {
      final accepted = await widget.reportClick(adId);
      if (!accepted) _reported.remove(adId);
      return accepted;
    } catch (error, stackTrace) {
      _reported.remove(adId);
      Log.e('广告上报异常, 不展示感谢', error: error, stackTrace: stackTrace);
      return false;
    }
  }

  Future<void> _openAd(AdItem ad) async {
    final user = AccountService.instance.user.value;
    if (_opening || (user?.isVip ?? false)) return;
    final visit = ++_visit;
    final userId = user?.userId;
    final listRoute = ModalRoute.of(context);
    final adId = ad.adId;
    _dismissThanks();
    _opening = true;
    final route = MaterialPageRoute<void>(
      builder: (_) => widget.buildAdPage(ad),
    );
    try {
      final popped = Navigator.of(context).push<void>(route);
      final report = ad.loggedIn && adId != null && _reported.add(adId)
          ? _report(adId)
          : Future<bool>.value(false);
      await popped;
      // push 的 Future 在 pop 开始时已完成, completed 才表示退出转场结束.
      await route.completed;
      if (!mounted) return;
      _opening = false;
      final accepted = await report;
      if (!mounted || visit != _visit) return;
      final currentUser = AccountService.instance.user.value;
      if (currentUser?.userId != userId || (currentUser?.isVip ?? false)) return;
      if (accepted && adId != null) {
        setState(() {
          _accepted.add(adId);
          _showThanks = _foreground && (listRoute?.isCurrent ?? false);
        });
        if (_showThanks) Log.i('返回广告列表, 展示 CC 娘扶边感谢 $adId');
      }
    } catch (error, stackTrace) {
      Log.e('打开或返回广告页失败', error: error, stackTrace: stackTrace);
    } finally {
      if (mounted && visit == _visit) _opening = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        FutureBuilder<List<AdItem>>(
          future: _ads,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const LoadingWidget();
            }
            if (snapshot.hasError) {
              return ErrorWidgetView(message: '广告加载失败', onRetry: _reload);
            }
            final ads = (snapshot.data ?? const <AdItem>[])
                .where((ad) => !_accepted.contains(ad.adId)).toList();
            if (ads.isEmpty) {
              return EmptyWidget(
                message: _accepted.isEmpty ? '广告暂时不可用' : '感谢支持, 本次广告已看完',
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: ads.length + 1,
              separatorBuilder: (context, index) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                if (index == ads.length) return const AdDisclaimer();
                final ad = ads[index];
                return InkWell(
                  key: ValueKey('ad-${ad.adId ?? ad.linkUrl}'),
                  onTap: () => unawaited(_openAd(ad)),
                  child: CachedNetworkImage(
                    imageUrl: ad.imageUrl,
                    fit: BoxFit.fitWidth,
                    placeholder: (context, url) => const AspectRatio(
                      aspectRatio: 10,
                      child: ColoredBox(color: Colors.black12),
                    ),
                    errorWidget: (context, url, error) => const AspectRatio(
                      aspectRatio: 10,
                      child: Center(child: Icon(Icons.broken_image_outlined)),
                    ),
                  ),
                );
              },
            );
          },
        ),
        if (_showThanks)
          CcPeekThanks(key: ValueKey(_visit), onDismiss: _dismissThanks),
      ],
    );
  }
}
