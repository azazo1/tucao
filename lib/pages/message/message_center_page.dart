import 'package:flutter/material.dart';
import 'package:tucao/common/adaptive.dart';
import 'package:tucao/pages/message/inbox_view.dart';
import 'package:tucao/pages/message/system_list_view.dart';

/// 私信页.
///
/// 站点的消息模块分私信与系统公告两块, 这里同样用两个标签切换: 私信是
/// 用户之间的会话, 系统是站点单方面发的公告.
class MessageCenterPage extends StatefulWidget {
  const MessageCenterPage({super.key});

  @override
  State<MessageCenterPage> createState() => _MessageCenterPageState();
}

class _MessageCenterPageState extends State<MessageCenterPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('私信'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [Tab(text: '私信'), Tab(text: '系统')],
        ),
      ),
      body: AdaptiveBody(
        child: TabBarView(
          controller: _tabs,
          children: const [InboxView(), SystemListView()],
        ),
      ),
    );
  }
}
