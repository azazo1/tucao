import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tucao/common/widgets/loading_widget.dart';
import 'package:tucao/http/ad_http.dart';
import 'package:tucao/pages/ad/ad_disclaimer.dart';
import 'package:tucao/pages/ad/ad_page.dart';
import 'package:tucao/services/account_service.dart';

typedef AdLoader = Future<List<AdItem>> Function({CancelToken? cancelToken});

/// 仅在非会员分支挂载, 避免感谢页仍在后台请求广告.
class AdFeed extends StatefulWidget {
  const AdFeed({super.key, required this.loadAds});

  final AdLoader loadAds;

  @override
  State<AdFeed> createState() => _AdFeedState();
}

class _AdFeedState extends State<AdFeed> {
  late Future<List<AdItem>> _ads;
  CancelToken? _request;
  final _reported = <String>{};

  @override
  void initState() {
    super.initState();
    _ads = _load();
  }

  Future<List<AdItem>> _load() {
    _request?.cancel('广告列表重新加载');
    final token = CancelToken();
    _request = token;
    return widget.loadAds(cancelToken: token);
  }

  @override
  void dispose() {
    _request?.cancel('离开广告列表或会员状态变化');
    super.dispose();
  }

  void _reload() {
    _reported.clear();
    setState(() => _ads = _load());
  }

  void _openAd(AdItem ad) {
    // 防止身份刚更新时旧列表的一次点击仍打开广告或上报.
    if (AccountService.instance.user.value?.isVip ?? false) return;
    final adId = ad.adId;
    if (ad.loggedIn && adId != null && _reported.add(adId)) {
      unawaited(AdHttp.reportClick(adId));
    }
    Get.to(() => AdPage(url: ad.linkUrl));
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<AdItem>>(
      future: _ads,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const LoadingWidget();
        }
        if (snapshot.hasError) {
          return ErrorWidgetView(message: '广告加载失败', onRetry: _reload);
        }
        final ads = snapshot.data ?? const <AdItem>[];
        if (ads.isEmpty) {
          return const EmptyWidget(message: '广告暂时不可用');
        }
        return ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: ads.length + 1,
          separatorBuilder: (context, index) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            if (index == ads.length) return const AdDisclaimer();
            final ad = ads[index];
            return InkWell(
              onTap: () => _openAd(ad),
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
    );
  }
}
