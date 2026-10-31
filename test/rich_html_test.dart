import 'dart:ui' show Color, TextAlign;

import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:tucao/common/constants.dart';
import 'package:tucao/common/rich_html/rich_content.dart';
import 'package:tucao/common/rich_html/rich_html_parser.dart';

List<RichBlock> _parse(String html) =>
    parseRichHtml(html_parser.parseFragment(html));

void main() {
  group('站点富文本解析', () {
    test('嵌套的颜色, 字号与加粗叠加到同一段文字上', () {
      // 片段取自档案 d7357 与 d7095.
      final blocks = _parse(
        '<p><span style="font-size:20px;"><span style="color:#999999;">'
        '介绍</span></span></p>'
        '<p><strong><span style="color:#e74c3c;">舞蹈</span></strong></p>'
        '<p><font color="#e74c3c"><b>翻唱</b></font></p>',
      );
      expect(blocks, hasLength(3));
      final intro = (blocks[0] as RichParagraph).spans.single.style;
      expect(intro.fontSize, 20);
      expect(intro.color, const Color(0xFF999999));
      for (final block in blocks.skip(1)) {
        final style = (block as RichParagraph).spans.single.style;
        expect(style.bold, isTrue);
        expect(style.color, const Color(0xFFE74C3C));
      }
    });

    test('空段落记成空行, 首尾空行去掉', () {
      final blocks = _parse(
        '<p>&nbsp;</p><p>上</p><p>&nbsp;</p><p>下</p><p>&nbsp;</p>',
      );
      expect(blocks.map((e) => e.runtimeType).toList(), [
        RichParagraph,
        RichSpacer,
        RichParagraph,
      ]);
    });

    test('源码里的缩进与换行折成空格, br 保留换行', () {
      final blocks = _parse('<p>\n  第一行  <br>\n  第二行\n</p>');
      expect((blocks.single as RichParagraph).text, '第一行\n第二行');
    });

    test('还原 Cloudflare 混淆的邮箱并生成邮箱链接', () {
      final blocks = _parse(
        '<p>邮箱 <a href="/cdn-cgi/l/email-protection" class="__cf_email__" '
        'data-cfemail="7200175c060711131d32151f131b1e5c111d1f">'
        '[email&#160;protected]</a></p>',
      );
      final spans = (blocks.single as RichParagraph).spans;
      expect(spans.last.text, 're.tucao@gmail.com');
      expect(spans.last.style.url, 'mailto:re.tucao@gmail.com');
    });

    test('链接补成绝对地址, 不安全的协议不当链接', () {
      final blocks = _parse(
        '<p><a href="/play/h6157/">#2013</a>'
        '<a href="javascript:alert(1)">坏链接</a></p>',
      );
      final spans = (blocks.single as RichParagraph).spans;
      expect(spans[0].style.url, '${Constants.baseUrl}play/h6157/');
      expect(spans[1].style.url, isNull);
    });

    test('图片独立成块, 带上百分比宽度与段落对齐', () {
      final blocks = _parse(
        '<p style="text-align:center">前<img src="/a.jpg" '
        'style="width: 50%;">后</p>',
      );
      expect(blocks, hasLength(3));
      final row = blocks[1] as RichImageRow;
      expect(row.images.single.url, '${Constants.baseUrl}a.jpg');
      expect(row.images.single.widthFactor, 0.5);
      expect(row.align, TextAlign.center);
      expect((blocks[2] as RichParagraph).align, TextAlign.center);
    });

    test('同一段落里相邻的图片排成一行, 文字与换行把它们隔开', () {
      // 结构取自档案 d7320: 五张 20% 宽的截图各自包在链接里, 并排贴在一段.
      const link = '<a href="/s.jpg"><img src="/s.jpg" style="width: 20%;"></a>';
      final blocks = _parse(
        '<p><span>${List.filled(5, link).join(' ')}</span></p>'
        '<p><img src="/a.jpg"><br><img src="/b.jpg">文字<img src="/c.jpg"></p>',
      );
      final rows = blocks.whereType<RichImageRow>().toList();
      expect(rows.first.images, hasLength(5));
      expect(rows.first.images.every((e) => e.widthFactor == 0.2), isTrue);
      expect(rows.skip(1).map((e) => e.images.length), [1, 1, 1]);
      expect(blocks.whereType<RichParagraph>().single.text, '文字');
    });

    test('em 字号相对父元素换算', () {
      final blocks = _parse(
        '<p><span style="font-size:20px"><span style="font-size:1.5em">'
        '大</span></span></p>',
      );
      expect((blocks.single as RichParagraph).spans.single.style.fontSize, 30);
    });
  });
}
