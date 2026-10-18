import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tucao/pages/ad/ad_page.dart';

/// 首页标题栏里的广告入口.
///
/// 点击后进入应用内广告页, 用 WebView 打开官方的推广链接,
/// 不参与应用内其他导航, 也不阻塞正常使用.
class AdEntryButton extends StatelessWidget {
  const AdEntryButton({super.key});

  /// 官网评论区的推广链接.
  static const _url =
      'https://equity.tmall.com/tm?agentId=2a0b947f82b04857'
      '&bc_fl_src=tmall_market_llb_1_2700830&llbPlatform=_pube&llbOsd=1'
      '&di=__IDFA__&dim=__IMEI__&oaid=__OAID__&caid=__CAID__&sy=llb';

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 10),
      child: Material(
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFFF8A3D), Color(0xFFE52958)],
            ),
          ),
          child: InkWell(
            onTap: () => Get.to(() => const AdPage(url: _url)),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.redeem, size: 14, color: Colors.white),
                  SizedBox(width: 3),
                  Text(
                    '广告',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
