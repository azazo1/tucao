import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tucao/common/widgets/loading_widget.dart';
import 'package:tucao/http/ad_http.dart';
import 'package:tucao/pages/ad/ad_actions.dart';
import 'package:tucao/pages/ad/ad_disclaimer.dart';
import 'package:tucao/pages/ad/ad_page.dart';

/// 应用内广告列表.
///
/// 与官方客户端的首页一致, 把站点广告位里的多条广告图依次展示,
/// 点某一条后进入应用内 WebView 打开对应链接.
class AdListPage extends StatefulWidget {
  const AdListPage({super.key});

  @override
  State<AdListPage> createState() => _AdListPageState();
}

class _AdListPageState extends State<AdListPage> {
  late Future<List<AdItem>> _ads;

  @override
  void initState() {
    super.initState();
    _ads = AdHttp.fetchHomeAds();
  }

  void _reload() {
    setState(() => _ads = AdHttp.fetchHomeAds());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('广告'),
        actions: [
          TextButton(
            onPressed: () => confirmDisableAd(context),
            child: const Text('取消广告'),
          ),
        ],
      ),
      body: FutureBuilder<List<AdItem>>(
        future: _ads,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const LoadingWidget();
          }
          if (snapshot.hasError) {
            return ErrorWidgetView(
              message: '广告加载失败',
              onRetry: _reload,
            );
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
              if (index == ads.length) {
                return const AdDisclaimer();
              }
              final ad = ads[index];
              return InkWell(
                onTap: () => Get.to(() => AdPage(url: ad.linkUrl)),
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
    );
  }
}
