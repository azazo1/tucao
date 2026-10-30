import 'package:flutter/material.dart';
import 'package:tucao/utils/clipboard.dart';

/// 让一段内容可以自由选择, 并在选择菜单里提供整段复制.
///
/// [text] 是选择菜单里 "复制全文" 要复制的内容, 由调用方决定是否包含标题.
class CopySelectionArea extends StatelessWidget {
  const CopySelectionArea({
    super.key,
    required this.text,
    required this.child,
    this.label = '复制全文',
  });

  final String text;

  final Widget child;

  final String label;

  @override
  Widget build(BuildContext context) {
    return SelectionArea(
      contextMenuBuilder: (menuContext, state) {
        final buttonItems = state.contextMenuButtonItems;
        buttonItems.add(
          ContextMenuButtonItem(
            label: label,
            onPressed: () {
              state.hideToolbar();
              state.clearSelection();
              copyText(context, text);
            },
          ),
        );
        return AdaptiveTextSelectionToolbar.buttonItems(
          anchors: state.contextMenuAnchors,
          buttonItems: buttonItems,
        );
      },
      child: child,
    );
  }
}
