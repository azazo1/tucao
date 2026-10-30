import 'package:flutter_test/flutter_test.dart';
import 'package:tucao/models/reply.dart';
import 'package:tucao/pages/reply/reply_copy.dart';

void main() {
  test('文字与站点表情转成可读文本', () {
    final text = replyCopyText(
      _reply('吵架变打架<img src="/statics/images/smilies/滑稽.gif" />'),
    );

    expect(text, '吵架变打架[滑稽]');
  });

  test('评论图片写成 Markdown 并单独成行', () {
    final text = replyCopyText(_reply('看图<img src="/uploadfile/a.png">继续'));

    final lines = text.split('\n');
    expect(lines, hasLength(3));
    expect(lines[0], '看图');
    expect(lines[1], startsWith('![图片]('));
    expect(lines[1], endsWith('/uploadfile/a.png)'));
    expect(lines[2], '继续');
  });

  test('连续图片各自占一行, 中间不留空行', () {
    final text = replyCopyText(
      _reply('<img src="/uploadfile/a.png"><img src="/uploadfile/b.png">'),
    );

    final lines = text.split('\n');
    expect(lines, hasLength(2));
    expect(lines[0], endsWith('/uploadfile/a.png)'));
    expect(lines[1], endsWith('/uploadfile/b.png)'));
  });

  test('楼中楼只复制正文, 不加回复对象前缀', () {
    final text = replyCopyText(_reply('被回复的内容', replyUserName: '楼主'));

    expect(text, '被回复的内容');
  });

  test('HTML 实体还原后进入剪贴板', () {
    expect(replyCopyText(_reply('a &amp; b')), 'a & b');
  });

  test('空正文返回空文本', () {
    expect(replyCopyText(_reply('')), isEmpty);
  });
}

ReplyModel _reply(String content, {String replyUserName = ''}) {
  return ReplyModel(
    id: '1',
    commentId: 'content_1',
    userId: 100,
    userName: '测试用户',
    content: content,
    replyId: replyUserName.isEmpty ? 0 : 1,
    replyUserName: replyUserName,
  );
}
