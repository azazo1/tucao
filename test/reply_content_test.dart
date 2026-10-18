import 'package:flutter_test/flutter_test.dart';
import 'package:tucao/pages/reply/reply_content.dart';

void main() {
  test('解析站点表情与相邻文字', () {
    final content = parseReplyContent(
      '吵架变打架<img src=/statics/images/smilies/滑稽.gif /><br>下一行',
    );

    expect(content.parts, hasLength(3));
    expect((content.parts[0] as ReplyTextPart).text, '吵架变打架');
    final emoji = content.parts[1] as ReplyEmojiPart;
    expect(emoji.name, '滑稽');
    expect(emoji.url, endsWith('/statics/images/smilies/滑稽.gif'));
    expect((content.parts[2] as ReplyTextPart).text, '\n下一行');
  });

  test('普通标签被清理, 非表情图片保留占位', () {
    final content = parseReplyContent(
      '<a>链接</a><img src="https://example.com/a.png">',
    );

    expect(content.parts, hasLength(1));
    expect((content.parts.first as ReplyTextPart).text, '链接[图片]');
  });

  test('纯文本清洗保留换行并还原实体', () {
    expect(cleanReplyContent('a<br>b &amp; c'), 'a\nb & c');
  });
}
