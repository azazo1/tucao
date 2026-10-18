import 'package:flutter_test/flutter_test.dart';
import 'package:tucao/http/update_http.dart';
import 'package:tucao/utils/version.dart';

void main() {
  group('版本号比较', () {
    test('忽略 v 前缀与构建元数据', () {
      expect(Version.compare('v1.2.0', '1.2.0'), 0);
      expect(Version.compare('1.2.0+3', '1.2.0'), 0);
      expect(Version.compare('v1.2.0-a1b2c3d', 'v1.2.0'), 0);
    });

    test('按数字段逐段比较', () {
      expect(Version.compare('1.10.0', '1.9.9'), greaterThan(0));
      expect(Version.compare('2.0.0', '1.99.99'), greaterThan(0));
      expect(Version.compare('1.2', '1.2.0'), 0);
      expect(Version.isNewer(current: '1.2.0', candidate: 'v1.3.0'), isTrue);
      expect(Version.isNewer(current: '1.2.0', candidate: 'v1.2.0'), isFalse);
      expect(Version.isNewer(current: 'v1.3.0', candidate: '1.2.0'), isFalse);
    });
  });

  group('Release 解析', () {
    test('读取标签, 正文与发布页', () {
      final release = UpdateHttp.parseRelease({
        'tag_name': 'v1.2.0',
        'name': '吐槽 v1.2.0',
        'body': '本版本的说明',
        'html_url': 'https://github.com/azazo1/tucao/releases/tag/v1.2.0',
        'prerelease': false,
      });
      expect(release, isNotNull);
      expect(release!.tagName, 'v1.2.0');
      expect(release.body, '本版本的说明');
      expect(release.pageUrl, endsWith('/v1.2.0'));
    });

    test('忽略预发布与缺字段的响应', () {
      expect(UpdateHttp.parseRelease(null), isNull);
      expect(UpdateHttp.parseRelease({'tag_name': 'v1.2.0'}), isNull);
      expect(
        UpdateHttp.parseRelease({
          'tag_name': 'v1.3.0-rc1',
          'html_url': 'https://github.com/azazo1/tucao/releases/tag/v1.3.0-rc1',
          'prerelease': true,
        }),
        isNull,
      );
    });
  });
}
