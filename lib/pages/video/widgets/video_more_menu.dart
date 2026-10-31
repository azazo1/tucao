import 'package:flutter/material.dart';
import 'package:tucao/common/widgets/page_more_menu.dart';
import 'package:tucao/utils/site_links.dart';

/// 视频页的三点菜单, 复制内容里不放入播放直链或账号信息.
class VideoMoreMenu extends StatelessWidget {
  const VideoMoreMenu({
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

  /// 视频页自己的浏览器打开流程, 打开前会暂停播放.
  final VoidCallback onOpenWebsite;
  final VoidCallback? onDownload;

  /// 重载播放器与页面信息, 为空时该项禁用.
  final VoidCallback? onRestart;

  /// 屏蔽或取消屏蔽当前内容, 为空时不显示入口.
  final VoidCallback? onBlock;

  /// 当前内容是否已经被屏蔽.
  final bool blocked;

  @override
  Widget build(BuildContext context) {
    return PageMoreMenu(
      uri: SiteLinks.video(hid, part: part),
      tooltip: '视频操作',
      onOpenInBrowser: onOpenWebsite,
      leading: [
        PageMenuAction(
          icon: Icons.restart_alt,
          label: '重启播放器',
          onSelected: onRestart,
        ),
        PageMenuAction(
          icon: Icons.download_outlined,
          label: '下载缓存',
          onSelected: onDownload,
        ),
      ],
      trailing: [
        if (onBlock != null)
          PageMenuAction(
            icon: blocked ? Icons.visibility_outlined : Icons.block,
            label: blocked ? '取消屏蔽' : '屏蔽此内容',
            onSelected: onBlock,
            destructive: !blocked,
          ),
      ],
    );
  }
}
