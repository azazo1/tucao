import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tucao/http/ad_http.dart';
import 'package:tucao/pages/ad/ad_actions.dart';
import 'package:tucao/pages/ad/widgets/ad_feed.dart';
import 'package:tucao/pages/ad/widgets/vip_thanks_panel.dart';
import 'package:tucao/services/account_service.dart';

/// 广告入口: 破会员看感谢页, 其他访客保持原广告列表.
class AdListPage extends StatelessWidget {
  const AdListPage({super.key, this.loadAds = AdHttp.fetchHomeAds});

  final AdLoader loadAds;

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
      body: Obx(() {
        final user = AccountService.instance.user.value;
        if (user?.isVip ?? false) {
          return VipThanksPanel(key: ValueKey('thanks-${user!.userId}'));
        }
        // 切换账号时重建列表, 不沿用上一个账号的登录标记与点击集合.
        return AdFeed(key: ValueKey(user?.userId), loadAds: loadAds);
      }),
    );
  }
}
