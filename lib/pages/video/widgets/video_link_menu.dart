import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tucao/utils/logger.dart';
import 'package:tucao/utils/site_links.dart';

enum _LinkAction { block, restart, copy, browser, download }

/// 视频操作菜单, 复制内容里不放入播放直链或账号信息.
class VideoLinkMenu extends StatelessWidget {
  const VideoLinkMenu({
    super.key,
    required this.hid,
    required this.part,
    required this.onOpenWebsite,
    this.onDownload,
    this.onRestart,
    this.onBlock,
    this.blocked = false,
  });

  final String hid;
  final int part;
  final VoidCallback onOpenWebsite;
  final VoidCallback? onDownload;

  /// 重载播放器与页面信息, 为空时不显示入口.
  final VoidCallback? onRestart;

  /// 屏蔽或取消屏蔽当前内容, 为空时不显示入口.
  final VoidCallback? onBlock;

  /// 当前内容是否已经被屏蔽.
  final bool blocked;

  Future<void> _copy(BuildContext context, Uri uri) async {
    try {
      await Clipboard.setData(ClipboardData(text: uri.toString()));
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('链接已复制')));
    } catch (error, stackTrace) {
      Log.e('复制视频链接失败', error: error, stackTrace: stackTrace);
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('复制失败, 请重试')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final uri = SiteLinks.video(hid, part: part);
    return PopupMenuButton<_LinkAction>(
      enabled: uri != null,
      tooltip: '视频操作',
      icon: const Icon(Icons.more_vert),
      onSelected: (action) {
        switch (action) {
          case _LinkAction.block:
            onBlock?.call();
          case _LinkAction.restart:
            onRestart?.call();
          case _LinkAction.copy:
            if (uri != null) {
              _copy(context, uri);
            }
          case _LinkAction.browser:
            onOpenWebsite();
          case _LinkAction.download:
            onDownload?.call();
        }
      },
      itemBuilder: (context) {
        final scheme = Theme.of(context).colorScheme;
        return [
          PopupMenuItem(
            value: _LinkAction.restart,
            enabled: onRestart != null,
            child: const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.restart_alt),
              title: Text('重启播放器'),
            ),
          ),
          PopupMenuItem(
            value: _LinkAction.download,
            enabled: onDownload != null,
            child: const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.download_outlined),
              title: Text('下载缓存'),
            ),
          ),
          const PopupMenuItem(
            value: _LinkAction.copy,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.link),
              title: Text('复制链接'),
            ),
          ),
          const PopupMenuItem(
            value: _LinkAction.browser,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.open_in_browser),
              title: Text('浏览器打开'),
            ),
          ),
          if (onBlock != null)
            PopupMenuItem(
              value: _LinkAction.block,
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                iconColor: blocked ? null : scheme.error,
                textColor: blocked ? null : scheme.error,
                leading: Icon(
                  blocked ? Icons.visibility_outlined : Icons.block,
                ),
                title: Text(blocked ? '取消屏蔽' : '屏蔽此内容'),
              ),
            ),
        ];
      },
    );
  }
}
