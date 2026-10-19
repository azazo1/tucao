import 'package:flutter_test/flutter_test.dart';
import 'package:tucao/http/update_http.dart';
import 'package:tucao/models/dev_build.dart';
import 'package:tucao/models/release_asset.dart';
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

  group('开发版构建解析', () {
    test('从说明里读出版本号与发布页', () {
      final build = DevBuild.fromJson({
        'tag_name': 'dev-latest',
        'name': '吐槽 最新构建 v1.2.3-a1b2c3d',
        'body':
            '分支 `main` 最新一次 push 的预发布.\n\n'
            '- 提交: [`a1b2c3d`](https://github.com/azazo1/tucao/commit/a1b2c3d)\n'
            '- 构建版本: `v1.2.3-a1b2c3d`\n',
        'html_url': 'https://github.com/azazo1/tucao/releases/tag/dev-latest',
        'prerelease': true,
      });
      expect(build, isNotNull);
      expect(build!.buildVersion, 'v1.2.3-a1b2c3d');
      expect(build.pageUrl, endsWith('/dev-latest'));
    });

    test('说明没有版本行时退回标题', () {
      final build = DevBuild.fromJson({
        'name': '吐槽 最新构建 v1.2.3-def5678',
        'body': '',
        'html_url': 'https://github.com/azazo1/tucao/releases/tag/dev-latest',
      });
      expect(build, isNotNull);
      expect(build!.buildVersion, 'v1.2.3-def5678');
    });

    test('缺少发布页时返回 null', () {
      expect(DevBuild.fromJson({'name': '吐槽 最新构建 v1.2.3'}), isNull);
    });
  });

  group('开发版更新判定', () {
    const build = DevBuild(
      buildVersion: 'v1.2.3-a1b2c3d',
      body: '',
      pageUrl: 'https://github.com/azazo1/tucao/releases/tag/dev-latest',
    );

    test('版本串一致时为最新', () {
      expect(build.statusFor('v1.2.3-a1b2c3d'), DevBuildStatus.latest);
      expect(build.statusFor('1.2.3-a1b2c3d'), DevBuildStatus.latest);
    });

    test('同一基础版本的不同提交算更新', () {
      expect(build.statusFor('v1.2.3-def5678'), DevBuildStatus.outdated);
      expect(build.statusFor('v1.2.3'), DevBuildStatus.outdated);
    });

    test('基础版本更高时视为本机构建更新', () {
      expect(build.statusFor('v1.3.0-def5678'), DevBuildStatus.localNewer);
    });

    test('本地构建无法比较', () {
      expect(build.statusFor('dev-build'), DevBuildStatus.unknown);
    });

    test('CI 版本号缺失时无法比较', () {
      const missing = DevBuild(buildVersion: '', body: '', pageUrl: '');
      expect(missing.statusFor('v1.2.3-a1b2c3d'), DevBuildStatus.unknown);
    });
  });

  group('产物与架构选择', () {
    Map<String, dynamic> releaseJson(List<Map<String, dynamic>> assets) => {
      'tag_name': 'v1.3.0',
      'name': '吐槽 v1.3.0',
      'body': '说明',
      'html_url': 'https://github.com/azazo1/tucao/releases/tag/v1.3.0',
      'assets': assets,
    };

    Map<String, dynamic> apk(String name, {int size = 1024}) => {
      'name': name,
      'size': size,
      'browser_download_url': 'https://example.com/$name',
    };

    test('读取产物列表, 丢掉名字不可用的条目', () {
      final release = UpdateHttp.parseRelease(
        releaseJson([
          apk('tucao-1.3.0-android-arm64-v8a.apk'),
          apk('SHA256SUMS'),
          {'name': '../escape.apk', 'browser_download_url': 'https://e/1'},
          {'name': 'no-url.apk'},
        ]),
      );
      expect(release, isNotNull);
      expect(release!.assets.length, 1);
      expect(release.assets.single.name, endsWith('arm64-v8a.apk'));
    });

    test('没有 assets 字段时按空列表处理', () {
      final release = UpdateHttp.parseRelease({
        'tag_name': 'v1.3.0',
        'html_url': 'https://github.com/azazo1/tucao/releases/tag/v1.3.0',
      });
      expect(release!.assets, isEmpty);
      expect(release.apkFor(['arm64-v8a']), isNull);
    });

    test('按设备 ABI 的优先顺序取包', () {
      final release = UpdateHttp.parseRelease(
        releaseJson([
          apk('tucao-1.3.0-android-armeabi-v7a.apk'),
          apk('tucao-1.3.0-android-arm64-v8a.apk'),
        ]),
      )!;
      expect(
        release.apkFor(['arm64-v8a', 'armeabi-v7a'])?.name,
        'tucao-1.3.0-android-arm64-v8a.apk',
      );
      expect(
        release.apkFor(['armeabi-v7a'])?.name,
        'tucao-1.3.0-android-armeabi-v7a.apk',
      );
      // 设备报出应用没发布的架构时退回到发布页.
      expect(release.apkFor(['x86']), isNull);
      expect(release.apkFor(const []), isNull);
    });

    test('开发版构建同样解析产物', () {
      final build = DevBuild.fromJson({
        'name': '吐槽 最新构建 v1.2.3-a1b2c3d',
        'body': '',
        'html_url': 'https://github.com/azazo1/tucao/releases/tag/dev-latest',
        'assets': [apk('tucao-1.2.3-android-x86_64.apk')],
      });
      expect(build, isNotNull);
      expect(build!.apkFor(['x86_64'])?.name, 'tucao-1.2.3-android-x86_64.apk');
      expect(build.apkFor(['arm64-v8a']), isNull);
    });

    test('产物体积按可读单位展示', () {
      expect(
        const ReleaseAsset(name: 'a.apk', size: 0, downloadUrl: 'u').sizeText,
        '大小未知',
      );
      expect(
        const ReleaseAsset(
          name: 'a.apk',
          size: 2048,
          downloadUrl: 'u',
        ).sizeText,
        '2 KB',
      );
      expect(
        const ReleaseAsset(
          name: 'a.apk',
          size: 20526836,
          downloadUrl: 'u',
        ).sizeText,
        '19.6 MB',
      );
    });
  });
}
