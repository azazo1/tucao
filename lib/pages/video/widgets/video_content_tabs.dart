import 'package:flutter/material.dart';
import 'package:tucao/pages/reply/reply_page.dart';
import 'package:tucao/pages/reply/reply_controller.dart';

/// 只切换播放器下方内容, 评论首次选中时才创建.
class VideoContentTabs extends StatefulWidget {
  const VideoContentTabs({
    super.key,
    required this.controller,
    required this.introduction,
    required this.typeId,
    required this.hid,
    this.part = 0,
    this.replyControllerFactory,
  });

  final TabController controller;
  final Widget introduction;
  final int typeId;
  final String hid;
  final int part;
  final ReplyController Function(int typeId, String hid, int part)?
  replyControllerFactory;

  @override
  State<VideoContentTabs> createState() => _VideoContentTabsState();
}

class _VideoContentTabsState extends State<VideoContentTabs> {
  bool _visitedReplies = false;

  @override
  void initState() {
    super.initState();
    _visitedReplies = widget.controller.index == 1;
    widget.controller.addListener(_onTabChanged);
  }

  void _onTabChanged() {
    if (!_visitedReplies && widget.controller.index == 1) {
      setState(() => _visitedReplies = true);
    }
  }

  @override
  void didUpdateWidget(covariant VideoContentTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onTabChanged);
      widget.controller.addListener(_onTabChanged);
    }
    if (oldWidget.hid != widget.hid || oldWidget.typeId != widget.typeId) {
      _visitedReplies = widget.controller.index == 1;
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTabChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TabBar(
          controller: widget.controller,
          dividerHeight: 0.5,
          tabs: const [
            Tab(
              child: Text('简介', maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            Tab(
              child: Text('评论', maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: widget.controller,
            children: [
              _KeepAliveContent(child: widget.introduction),
              if (_visitedReplies && widget.typeId > 0 && widget.hid.isNotEmpty)
                ReplyPanel(
                  key: ValueKey((widget.hid, widget.typeId)),
                  typeId: widget.typeId,
                  hid: widget.hid,
                  part: widget.part,
                  controllerFactory: widget.replyControllerFactory,
                )
              else
                const SizedBox.shrink(),
            ],
          ),
        ),
      ],
    );
  }
}

class _KeepAliveContent extends StatefulWidget {
  const _KeepAliveContent({required this.child});

  final Widget child;

  @override
  State<_KeepAliveContent> createState() => _KeepAliveContentState();
}

class _KeepAliveContentState extends State<_KeepAliveContent>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
