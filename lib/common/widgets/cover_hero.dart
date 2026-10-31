import 'package:flutter/material.dart';

/// 从列表封面飞进播放页的共享元素过渡.
///
/// 同一个视频可能同时出现在继续观看条, 网格和保活的其他标签页里, 这些卡片
/// 如果都带同一个 hero tag 会让 Hero 断言失败. 因此只给被点的那一张卡片
/// 发一个一次性的 tag, 再通过路由参数带给播放页.
abstract final class CoverHero {
  /// 路由参数里 hero tag 的键.
  static const parameter = 'hero';

  static int _seq = 0;

  /// 为一次点击生成新的 tag.
  static String next(String hid) => 'cover-$hid-${++_seq}';

  /// 飞行途中一直画列表上清晰的那张封面.
  ///
  /// 播放页那一端是模糊压暗的底图, 用它飞会半路变糊, 落地后再交给播放页自己淡出.
  static Widget shuttle(
    BuildContext flightContext,
    Animation<double> animation,
    HeroFlightDirection direction,
    BuildContext fromContext,
    BuildContext toContext,
  ) {
    final source = direction == HeroFlightDirection.push
        ? fromContext
        : toContext;
    return (source.widget as Hero).child;
  }

  /// 有 tag 时包一层 Hero, 没有时原样返回.
  static Widget wrap({String? tag, required Widget child}) {
    if (tag == null || tag.isEmpty) return child;
    return Hero(tag: tag, flightShuttleBuilder: shuttle, child: child);
  }
}

/// 给一张卡片保存它的一次性 hero tag.
///
/// [builder] 拿到当前 tag (没点过为空) 和发起函数; 点击时调用发起函数换一个新
/// tag 并立即重建, 同一帧里路由入栈, Hero 就能找到这张卡片的封面.
class HeroLaunch extends StatefulWidget {
  const HeroLaunch({super.key, required this.hid, required this.builder});

  final String hid;

  final Widget Function(
    BuildContext context,
    String? tag,
    String Function() launch,
  )
  builder;

  @override
  State<HeroLaunch> createState() => _HeroLaunchState();
}

class _HeroLaunchState extends State<HeroLaunch> {
  String? _tag;

  String _launch() {
    final tag = CoverHero.next(widget.hid);
    setState(() => _tag = tag);
    return tag;
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _tag, _launch);
}
