import 'package:flutter/material.dart';
import 'package:tucao/utils/clipboard.dart';
import 'package:tucao/utils/external_browser.dart';

/// 更多菜单里的一项.
class PageMenuAction {
  const PageMenuAction({
    required this.icon,
    required this.label,
    this.onSelected,
    this.destructive = false,
  });

  final IconData icon;
  final String label;

  /// 为空时该项显示为禁用.
  final VoidCallback? onSelected;

  /// 是否用错误色强调, 用于屏蔽一类操作.
  final bool destructive;
}

/// 页面右上角的三点菜单.
///
/// 自带复制链接与在浏览器中打开, 页面专属的操作通过 [leading] 与 [trailing]
/// 放在通用项的前后. [uri] 为空时整个菜单禁用.
class PageMoreMenu extends StatelessWidget {
  const PageMoreMenu({
    super.key,
    required this.uri,
    this.tooltip = '更多',
    this.onOpenInBrowser,
    this.leading = const [],
    this.trailing = const [],
  });

  /// 当前页面对应的站点地址, 只应由 `SiteLinks` 生成.
  final Uri? uri;

  final String tooltip;

  /// 自定义浏览器打开流程, 比如视频页需要先暂停播放; 为空时直接打开 [uri].
  final VoidCallback? onOpenInBrowser;

  final List<PageMenuAction> leading;
  final List<PageMenuAction> trailing;

  List<PageMenuAction> _actions(BuildContext context, Uri? uri) => [
    ...leading,
    PageMenuAction(
      icon: Icons.link,
      label: '复制链接',
      onSelected: uri == null ? null : () => copyText(context, uri.toString()),
    ),
    PageMenuAction(
      icon: Icons.open_in_browser,
      label: '在浏览器中打开',
      onSelected: uri == null
          ? null
          : onOpenInBrowser ?? () => openInBrowser(context, uri),
    ),
    ...trailing,
  ];

  @override
  Widget build(BuildContext context) {
    final uri = this.uri;
    final actions = _actions(context, uri);
    return PopupMenuButton<int>(
      enabled: uri != null,
      tooltip: tooltip,
      icon: const Icon(Icons.more_vert),
      onSelected: (index) => actions[index].onSelected?.call(),
      itemBuilder: (context) {
        final error = Theme.of(context).colorScheme.error;
        return [
          for (var i = 0; i < actions.length; i++)
            PopupMenuItem(
              value: i,
              enabled: actions[i].onSelected != null,
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                iconColor: actions[i].destructive ? error : null,
                textColor: actions[i].destructive ? error : null,
                leading: Icon(actions[i].icon),
                title: Text(actions[i].label),
              ),
            ),
        ];
      },
    );
  }
}
