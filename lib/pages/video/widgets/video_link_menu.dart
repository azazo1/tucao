import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tucao/utils/logger.dart';
import 'package:tucao/utils/site_links.dart';

enum _LinkAction { copy, browser }

/// 视频链接操作, 不把播放直链或账号信息放入复制内容.
class VideoLinkMenu extends StatelessWidget {
  const VideoLinkMenu({
    super.key,
    required this.hid,
    required this.part,
    required this.onOpenWebsite,
  });

  final String hid;
  final int part;
  final VoidCallback onOpenWebsite;

  Future<void> _copy(BuildContext context, Uri uri) async {
    try {
      await Clipboard.setData(ClipboardData(text: uri.toString()));
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('链接已复制')));
    } catch (error, stackTrace) {
      Log.e('复制视频链接失败', error: error, stackTrace: stackTrace);
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('复制失败, 请重试')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final uri = SiteLinks.video(hid, part: part);
    return PopupMenuButton<_LinkAction>(
      enabled: uri != null,
      tooltip: '视频链接',
      icon: const Icon(Icons.more_vert),
      onSelected: (action) {
        switch (action) {
          case _LinkAction.copy:
            if (uri != null) {
              _copy(context, uri);
            }
          case _LinkAction.browser:
            onOpenWebsite();
        }
      },
      itemBuilder: (context) => const [
        PopupMenuItem(
          value: _LinkAction.copy,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.link),
            title: Text('复制链接'),
          ),
        ),
        PopupMenuItem(
          value: _LinkAction.browser,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.open_in_browser),
            title: Text('浏览器打开'),
          ),
        ),
      ],
    );
  }
}
