import 'package:flutter_test/flutter_test.dart';
import 'package:tucao/plugin/player/player_error.dart';

void main() {
  group('解码回退', () {
    test('解码器打不开会被识别为回退', () {
      expect(
        PlayerError.codecFallback(
          'Could not open codec \'h264_mediacodec\', error: no device',
        ),
        isTrue,
      );
    });

    test('网络错误不是解码回退', () {
      expect(
        PlayerError.codecFallback('tcp: ffurl_write returned 0xffffff99'),
        isFalse,
      );
    });
  });

  group('缓存是否推进', () {
    test('缓存末尾没动说明网络没恢复', () {
      expect(
        PlayerError.cacheAdvanced(
          const Duration(seconds: 10),
          const Duration(seconds: 10),
        ),
        isFalse,
      );
      expect(
        PlayerError.cacheAdvanced(
          const Duration(seconds: 10),
          const Duration(seconds: 10, milliseconds: 300),
        ),
        isFalse,
      );
    });

    test('缓存末尾前进说明确实读到了新数据', () {
      expect(
        PlayerError.cacheAdvanced(
          const Duration(seconds: 10),
          const Duration(seconds: 11),
        ),
        isTrue,
      );
    });
  });

  group('缓存是否耗尽', () {
    test('缓存里还有余量时不算耗尽', () {
      // 出错后靠缓存还能再播几秒, 这时位置会继续走, 但不能当成恢复.
      expect(
        PlayerError.cacheDrained(
          const Duration(seconds: 10),
          const Duration(seconds: 15),
        ),
        isFalse,
      );
    });

    test('缓存快要吃光算耗尽', () {
      expect(
        PlayerError.cacheDrained(
          const Duration(seconds: 10),
          const Duration(seconds: 10, milliseconds: 200),
        ),
        isTrue,
      );
    });

    test('缓存信息缺失时按耗尽处理', () {
      expect(
        PlayerError.cacheDrained(const Duration(seconds: 10), Duration.zero),
        isTrue,
      );
    });
  });
}
