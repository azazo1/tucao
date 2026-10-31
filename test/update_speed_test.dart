import 'package:flutter_test/flutter_test.dart';
import 'package:tucao/services/update/update_speed_test.dart';

void main() {
  test('速度按排除首字节的传输耗时计算', () {
    const result = MirrorSpeedResult(
      bytes: 1024 * 1024,
      elapsed: Duration(milliseconds: 1000),
      firstByte: Duration(milliseconds: 500),
    );
    expect(result.ok, isTrue);
    expect(result.transferElapsed, const Duration(milliseconds: 500));
    expect(result.bytesPerSecond, closeTo(2 * 1024 * 1024, 1));
    expect(result.text, '2048 KB/s');
  });

  test('首字节缺失时按总耗时计算', () {
    const result = MirrorSpeedResult(
      bytes: 1024 * 100,
      elapsed: Duration(seconds: 1),
    );
    expect(result.bytesPerSecond, closeTo(102400, 1));
    expect(result.text, '100 KB/s');
  });

  test('失败时展示原因且速度为零', () {
    const result = MirrorSpeedResult(error: '测速超时');
    expect(result.ok, isFalse);
    expect(result.text, '测速超时');
    expect(result.bytesPerSecond, 0);
  });

  test('耗时为零时不除零', () {
    const result = MirrorSpeedResult(bytes: 100, elapsed: Duration.zero);
    expect(result.bytesPerSecond, 0);
  });

  test('到时限没读够时按已读部分估算并标注未测完', () {
    const result = MirrorSpeedResult(
      bytes: 512 * 1024,
      elapsed: Duration(seconds: 12),
      firstByte: Duration(milliseconds: 500),
      timedOut: true,
    );
    expect(result.ok, isTrue);
    expect(result.text, endsWith('(未测完)'));
    expect(result.bytesPerSecond, greaterThan(0));
  });
}
