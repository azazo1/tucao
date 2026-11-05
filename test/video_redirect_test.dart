import 'package:flutter_test/flutter_test.dart';
import 'package:tucao/models/video.dart';

void main() {
  test('详情接口的 url 指向别的视频时识别为转向条目', () {
    // 与 h4099155 详情接口的实际返回结构一致.
    final video = VideoModel.fromJson({
      'hid': '4099155',
      'url': '/play/h4070523/',
      'part': 1,
      'video': [
        {'': null, 'title': '【合集】to Love 出包王女 第四季【1-14】【简体字幕】'},
      ],
    });
    expect(video.redirectHid, '4070523');
  });

  test('url 是自己的播放页或缺失时不跳转', () {
    expect(
      VideoModel.fromJson({
        'hid': '4070523',
        'url': '/play/h4070523/',
      }).redirectHid,
      isNull,
    );
    expect(VideoModel.fromJson({'hid': '4107845'}).redirectHid, isNull);
  });
}
