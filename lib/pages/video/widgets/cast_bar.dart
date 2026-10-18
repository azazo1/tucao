import 'package:flutter/material.dart';
import 'package:tucao/services/cast/session.dart';
import 'package:tucao/utils/utils.dart';

/// 播放器上方的投屏状态条.
///
/// 只在投屏进行时出现, 显示电视端进度, 并提供暂停与退出.
class CastBar extends StatelessWidget {
  const CastBar({
    super.key,
    required this.session,
    required this.onToggle,
    required this.onStop,
  });

  final CastSession session;

  final VoidCallback onToggle;

  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final playing = session.state == CastState.playing;
    final state = switch (session.state) {
      CastState.connecting => '正在连接…',
      CastState.paused => '已暂停',
      CastState.failed => '投屏中断',
      _ => '正在投屏',
    };
    final position = Utils.formatDuration(session.position);
    final duration = session.duration > Duration.zero
        ? Utils.formatDuration(session.duration)
        : '--:--';
    return Material(
      color: Colors.black.withValues(alpha: 0.58),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Row(
          children: [
            const Icon(Icons.cast_connected, size: 18, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$state · ${session.device.name}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                  Text(
                    '$position / $duration',
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: playing ? '暂停投屏' : '继续投屏',
              visualDensity: VisualDensity.compact,
              onPressed: onToggle,
              icon: Icon(
                playing ? Icons.pause : Icons.play_arrow,
                color: Colors.white,
              ),
            ),
            IconButton(
              tooltip: '退出投屏',
              visualDensity: VisualDensity.compact,
              onPressed: onStop,
              icon: const Icon(Icons.stop_circle_outlined, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}
