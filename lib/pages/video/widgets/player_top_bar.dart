import 'dart:async';

import 'package:flutter/material.dart';

/// 全屏时画面顶部的信息条: 返回, 标题与分P, 当前时间, 以及额外按钮.
///
/// 横屏全屏会盖住系统状态栏, 时间放在这里, 看番时不用退出全屏看钟.
class PlayerTopBar extends StatelessWidget {
  const PlayerTopBar({
    super.key,
    required this.title,
    required this.onBack,
    this.subtitle,
    this.actions = const [],
  });

  final String title;

  /// 分P名等次要信息, 为空不显示.
  final String? subtitle;

  final VoidCallback onBack;

  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final subtitle = this.subtitle;
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black54, Colors.transparent],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(0, 0, 8, 12),
          child: Row(
            children: [
              IconButton(
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                tooltip: '退出全屏',
              ),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (subtitle != null && subtitle.isNotEmpty)
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
              ...actions,
              const SizedBox(width: 4),
              const _Clock(),
            ],
          ),
        ),
      ),
    );
  }
}

/// 只精确到分钟的时钟, 每到整分刷新一次.
class _Clock extends StatefulWidget {
  const _Clock();

  @override
  State<_Clock> createState() => _ClockState();
}

class _ClockState extends State<_Clock> {
  Timer? _timer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  /// 对齐到下一个整分, 避免时间显示比系统慢上几十秒.
  void _schedule() {
    final now = DateTime.now();
    final wait = Duration(seconds: 60 - now.second);
    _timer = Timer(wait, () {
      if (!mounted) {
        return;
      }
      setState(() => _now = DateTime.now());
      _schedule();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hour = _now.hour.toString().padLeft(2, '0');
    final minute = _now.minute.toString().padLeft(2, '0');
    return Text(
      '$hour:$minute',
      style: const TextStyle(color: Colors.white, fontSize: 13),
    );
  }
}
