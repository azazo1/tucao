import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tucao/pages/ad/ad_list_page.dart';

/// 首页标题栏里的广告入口.
///
/// 点击后进入应用内广告列表, 链接与图片都来自站点首页广告位,
/// 不参与应用内其他导航, 也不阻塞正常使用.
class AdEntryButton extends StatelessWidget {
  const AdEntryButton({super.key});

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
            onTap: () => Get.to(() => const AdListPage()),
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
