import 'package:flutter/material.dart';
import 'package:tucao/common/adaptive.dart';
import 'package:tucao/pages/message/comment_list_view.dart';

/// 评论页.
///
/// 站点在会员中心列出自己发表过的评论, 条目里带被评论内容的封面, 分区,
/// 标题与作者, 点按跳回原内容. 入口与私信并列, 都放在「我的」页.
class CommentPage extends StatelessWidget {
  const CommentPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('评论')),
      body: const AdaptiveBody(child: CommentListView()),
    );
  }
}
