import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tucao/http/ad_http.dart';
import 'package:tucao/pages/ad/ad_page.dart';
import 'package:tucao/utils/logger.dart';

/// 首页标题栏里的广告入口.
///
/// 点击时从站点首页的广告位解析目标链接, 再进入应用内广告页.
/// 链接不写死在客户端, 站长更换广告后自动跟随.
class AdEntryButton extends StatefulWidget {
  const AdEntryButton({super.key});

  @override
  State<AdEntryButton> createState() => _AdEntryButtonState();
}

class _AdEntryButtonState extends State<AdEntryButton> {
  bool _loading = false;

  Future<void> _open() async {
    if (_loading) {
      return;
    }
    setState(() => _loading = true);
    String? url;
    try {
      url = await AdHttp.fetchHomeAdLink();
    } catch (error, stackTrace) {
      Log.e('加载广告链接失败', error: error, stackTrace: stackTrace);
    }
    if (!mounted) {
      return;
    }
    setState(() => _loading = false);
    final target = url;
    if (target == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('广告暂时不可用')));
      return;
    }
    Get.to(() => AdPage(url: target));
  }

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
            onTap: _open,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_loading)
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  else
                    const Icon(Icons.redeem, size: 14, color: Colors.white),
                  const SizedBox(width: 3),
                  const Text(
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
