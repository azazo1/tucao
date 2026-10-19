import 'package:flutter_test/flutter_test.dart';
import 'package:tucao/common/constants.dart';
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

  test('普通标签被清理, 图片单独成段', () {
    final content = parseReplyContent(
      '<a>链接</a><img src="https://example.com/a.png">',
    );

    expect(content.parts, hasLength(2));
    expect((content.parts.first as ReplyTextPart).text, '链接');
    expect(
      (content.parts.last as ReplyImagePart).url,
      'https://example.com/a.png',
    );
  });

  test('图片相对地址补成绝对地址', () {
    final content = parseReplyContent(
      '<img src="/uploadfile/2023/0823/a.jpg" class="comment_pic">',
    );

    expect(content.parts, hasLength(1));
    expect(
      (content.parts.single as ReplyImagePart).url,
      endsWith('/uploadfile/2023/0823/a.jpg'),
    );
  });

  test('纯文本清洗保留换行并还原实体', () {
    expect(cleanReplyContent('a<br>b &amp; c'), 'a\nb & c');
  });

  test('站点用十六进制实体写的评论被还原', () {
    // 取自站点上的一条广告评论, 整条内容是十六进制实体.
    const raw =
        '&#x5144;&#x5f1f;&#x4eec;&#xff1a;&#x0068;&#x0074;&#x0074;&#x0070;';

    final text = (parseReplyContent(raw).parts.single as ReplyTextPart).text;
    expect(text, '兄弟们：http');
    expect(cleanReplyContent(raw), '兄弟们：http');
  });

  test('站外地址不会被当成表情', () {
    final content = parseReplyContent(
      '<img src="https://evil.example/smilies/x.gif">',
    );

    expect(content.parts.single, isA<ReplyImagePart>());
  });

  test('站外图片不被当成站点图片', () {
    // 站点自己的地址自动加载, 站外地址由界面等用户点击.
    expect(
      isSiteImage('${Constants.baseUrl}uploadfile/2023/0823/a.jpg'),
      isTrue,
    );
    expect(isSiteImage('https://tucao.my/uploadfile/a.jpg'), isTrue);
    expect(isSiteImage('https://cdn.tucao.my/uploadfile/a.jpg'), isTrue);
    expect(isSiteImage('https://evil.example/a.jpg'), isFalse);
    expect(isSiteImage('https://tucao.my.evil.example/a.jpg'), isFalse);
    expect(isSiteImage('javascript:alert(1)'), isFalse);
  });

  test('二次转义的实体再解一层', () {
    expect(cleanReplyContent('a&amp;#39;b'), "a'b");
  });
}
