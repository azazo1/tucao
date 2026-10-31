import 'package:flutter_test/flutter_test.dart';
import 'package:tucao/services/update/update_source.dart';

void main() {
  const apkUrl =
      'https://github.com/azazo1/tucao/releases/download/'
      'v1.5.0/tucao-1.5.0-android-arm64-v8a.apk';
  const mirrors = ['https://mirror-a.example', 'https://mirror-b.example'];

  test('自动源先镜像后官方', () {
    final list = UpdateSources.candidates(
      downloadUrl: apkUrl,
      source: UpdateSource.auto,
      mirrorPrefixes: mirrors,
    );
    expect(list, hasLength(mirrors.length + 1));
    for (var i = 0; i < mirrors.length; i++) {
      expect(list[i].toString(), '${mirrors[i]}/$apkUrl');
    }
    expect(list.last.toString(), apkUrl);
  });

  test('只走国内镜像时不带官方源', () {
    final list = UpdateSources.candidates(
      downloadUrl: apkUrl,
      source: UpdateSource.mirror,
      mirrorPrefixes: mirrors,
    );
    expect(list, hasLength(mirrors.length));
    expect(list.any((uri) => uri.host == 'github.com'), isFalse);
  });

  test('官方源只有原地址', () {
    final list = UpdateSources.candidates(
      downloadUrl: apkUrl,
      source: UpdateSource.github,
      mirrorPrefixes: mirrors,
    );
    expect(list.single.toString(), apkUrl);
  });

  test('没有启用镜像时自动源只剩官方', () {
    final list = UpdateSources.candidates(
      downloadUrl: apkUrl,
      source: UpdateSource.auto,
    );
    expect(list.single.toString(), apkUrl);
  });

  test('空白前缀不参与拼接', () {
    final list = UpdateSources.candidates(
      downloadUrl: apkUrl,
      source: UpdateSource.auto,
      mirrorPrefixes: const ['', '  ', 'https://mirror-a.example'],
    );
    expect(list, hasLength(2));
    expect(list.first.host, 'mirror-a.example');
  });

  test('非 GitHub 地址不套镜像', () {
    final list = UpdateSources.candidates(
      downloadUrl: 'https://example.com/a.apk',
      source: UpdateSource.auto,
      mirrorPrefixes: mirrors,
    );
    expect(list.single.toString(), 'https://example.com/a.apk');
  });

  test('地址不可用时不产生候选', () {
    expect(
      UpdateSources.candidates(
        downloadUrl: '',
        source: UpdateSource.auto,
        mirrorPrefixes: mirrors,
      ),
      isEmpty,
    );
  });
}
