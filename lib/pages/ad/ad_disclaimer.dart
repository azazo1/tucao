import 'package:flutter/material.dart';

/// 广告页底部的说明.
///
/// 广告来自官网广告位, 收益归属与结算由站点和广告平台决定,
/// 客户端无法确认当前入口是否真的能给站长带来收益, 这里如实说明.
class AdDisclaimer extends StatelessWidget {
  const AdDisclaimer({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Text(
        '本页广告来自吐槽官网广告位, 感谢你对站长的支持.\n'
        '当前广告页能否给站长带来收益暂时未知, 具体以站点和广告平台的结算为准.',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 12,
          height: 1.6,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
