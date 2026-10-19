import 'package:flutter/material.dart';
import 'package:tucao/common/adaptive.dart';
import 'package:tucao/pages/message/comment_list_view.dart';
import 'package:tucao/pages/message/inbox_view.dart';
import 'package:tucao/pages/message/system_list_view.dart';

/// 消息页.
///
/// 站点的消息分三块: 私信是用户之间的会话, 评论是自己发表过的评论, 系统是
/// 站点单方面发的公告. 评论在会员中心, 与私信不在同一个动作下, 页面结构也
/// 不同, 这里用三个标签并列.
class MessageCenterPage extends StatefulWidget {
  const MessageCenterPage({super.key});

  @override
  State<MessageCenterPage> createState() => _MessageCenterPageState();
}

class _MessageCenterPageState extends State<MessageCenterPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('消息'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [Tab(text: '私信'), Tab(text: '评论'), Tab(text: '系统')],
        ),
      ),
      body: AdaptiveBody(
        child: TabBarView(
          controller: _tabs,
          children: const [InboxView(), CommentListView(), SystemListView()],
        ),
      ),
    );
  }
}
