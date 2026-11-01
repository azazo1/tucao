import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tucao/models/video.dart';

void main() {
  const full =
      'https://a.tucaoav.cc/d/tucao_b2/新番/2019/【澄空學園&動漫國字幕組】魔法禁书目录Ⅲ'
      '【01-26】【繁體字幕】/[tucao][DMG&SumiSora][To_Aru_Majutsu_no_Index_Ⅲ]'
      '[01][720P][BIG5]_720p_x265.mp4';

  test('站点把地址按 & 截断时按原顺序拼回完整直链', () {
    // 与 h4079710 详情接口的实际返回结构一致.
    final json = jsonDecode('''
{"type":"video",
 "file":"https://a.tucaoav.cc/d/tucao_b2/新番/2019/【澄空學園",
 "動漫國字幕組】魔法禁书目录Ⅲ【01-26】【繁體字幕】/[tucao][DMG":null,
 "SumiSora][To_Aru_Majutsu_no_Index_Ⅲ][01][720P][BIG5]_720p_x265.mp4":null,
 "title":"p1"}
''');
    final part = VideoPart.fromJson((json as Map).cast<String, dynamic>());
    expect(part.file, full);
    expect(part.title, 'p1');
  });

  test('站点修好后完整直链保持原样', () {
    final part = VideoPart.fromJson({
      'type': 'video',
      'file': full,
      'title': 'p1',
    });
    expect(part.file, full);
  });
}
