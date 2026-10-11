import 'package:flutter_test/flutter_test.dart';
import 'package:tucao/models/api_response.dart';
import 'package:tucao/models/danmaku.dart';
import 'package:tucao/models/video.dart';
import 'package:tucao/utils/date_utils.dart';
import 'package:tucao/utils/utils.dart';

void main() {
  group('数字格式化', () {
    test('一万以下原样输出', () {
      expect(Utils.formatCount(0), '0');
      expect(Utils.formatCount(9999), '9999');
    });

    test('超过一万按万显示', () {
      expect(Utils.formatCount(10000), '1万');
      expect(Utils.formatCount(12345), '1.2万');
      expect(Utils.formatCount(1234567), '123.5万');
    });

    test('超过一亿按亿显示', () {
      expect(Utils.formatCount(123456789), '1.2亿');
    });
  });

  group('时长格式化', () {
    test('一小时以内', () {
      expect(Utils.formatSeconds(0), '00:00');
      expect(Utils.formatSeconds(65), '01:05');
      expect(Utils.formatSeconds(3599), '59:59');
    });

    test('超过一小时带小时位', () {
      expect(Utils.formatSeconds(3600), '1:00:00');
      expect(Utils.formatSeconds(3725), '1:02:05');
    });
  });

  group('相对时间', () {
    test('非法时间戳返回空串', () {
      expect(DateUtil.relative(0), '');
      expect(DateUtil.relative(-1), '');
    });

    test('刚发布显示刚刚', () {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      expect(DateUtil.relative(now), '刚刚');
    });

    test('按天数递减显示', () {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      expect(DateUtil.relative(now - 3600 * 3), '3小时前');
      expect(DateUtil.relative(now - 86400 * 2), '2天前');
    });
  });

  group('接口响应解析', () {
    test('code 为字符串时按字符串比较', () {
      final response = ApiResponse<int>.fromJson(
        {'code': '200', 'result': 7},
        (data) => data as int,
      );
      expect(response.success, isTrue);
      expect(response.result, 7);
    });

    test('失败响应带错误信息', () {
      final response = ApiResponse<int>.fromJson(
        {'code': '-403', 'msg': 'apikey error'},
        (data) => data as int,
      );
      expect(response.success, isFalse);
      expect(response.message, 'apikey error');
    });

    test('列表响应解析出总数与条目', () {
      final response = ListResponse<VideoModel>.fromJson({
        'code': '200',
        'total_count': 42,
        'result': [
          {'hid': '4107860', 'title': '测试视频', 'play': '11644', 'part': 2},
        ],
      }, VideoModel.fromJson);
      expect(response.success, isTrue);
      expect(response.total, 42);
      expect(response.list, hasLength(1));
      expect(response.list.first.hid, '4107860');
      expect(response.list.first.playCount, 11644);
      expect(response.list.first.partCount, 2);
    });

    test('result 为 null 时返回空列表', () {
      final response = ListResponse<VideoModel>.fromJson({
        'code': '200',
        'total_count': 0,
        'result': null,
      }, VideoModel.fromJson);
      expect(response.list, isEmpty);
    });
  });

  group('视频分P解析', () {
    test('自建源带直链', () {
      final part = VideoPart.fromJson({
        'type': 'video',
        'file': 'https://get.tucao.my/vertexforce1',
        'title': '第一话',
      });
      expect(part.isThirdParty, isFalse);
      expect(part.file, 'https://get.tucao.my/vertexforce1');
    });

    test('第三方源只有 vid 时判定为失效源', () {
      final part = VideoPart.fromJson({
        'type': 'youku',
        'vid': 'XMjg1ODcwMzg4',
        'title': '旧投稿',
      });
      expect(part.isThirdParty, isTrue);
      expect(part.vid, 'XMjg1ODcwMzg4');
    });
  });

  group('弹幕解析', () {
    test('按站点 p 属性解析出各字段', () {
      final danmaku = DanmakuModel.fromAttr(
        '141.4,2,25,16777215,1791720692',
        '测试弹幕',
      );
      expect(danmaku.time, 141.4);
      expect(danmaku.mode, 2);
      expect(danmaku.fontSize, 25);
      expect(danmaku.color, 16777215);
      expect(danmaku.timestamp, 1791720692);
      expect(danmaku.text, '测试弹幕');
    });

    test('字段缺失时取默认值', () {
      final danmaku = DanmakuModel.fromAttr('12.5', '短属性');
      expect(danmaku.time, 12.5);
      expect(danmaku.mode, 0);
      expect(danmaku.color, 0);
    });
  });
}
