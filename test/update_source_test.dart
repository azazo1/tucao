import 'package:flutter_test/flutter_test.dart';
import 'package:tucao/services/update/update_source.dart';

void main() {
  const apkUrl =
      'https://github.com/azazo1/tucao/releases/download/'
      'v1.5.0/tucao-1.5.0-android-arm64-v8a.apk';

  test('自动源先镜像后官方', () {
    final list = UpdateSources.candidates(
      downloadUrl: apkUrl,
      source: UpdateSource.auto,
    );
    expect(list, hasLength(UpdateSources.mirrors.length + 1));
    for (var i = 0; i < UpdateSources.mirrors.length; i++) {
      expect(list[i].toString(), '${UpdateSources.mirrors[i]}/$apkUrl');
    }
    expect(list.last.toString(), apkUrl);
  });

  test('只走国内镜像时不带官方源', () {
    final list = UpdateSources.candidates(
      downloadUrl: apkUrl,
      source: UpdateSource.mirror,
    );
    expect(list, hasLength(UpdateSources.mirrors.length));
    expect(list.any((uri) => uri.host == 'github.com'), isFalse);
  });

  test('官方源只有原地址', () {
    final list = UpdateSources.candidates(
      downloadUrl: apkUrl,
      source: UpdateSource.github,
    );
    expect(list.single.toString(), apkUrl);
  });

  test('非 GitHub 地址不套镜像', () {
    final list = UpdateSources.candidates(
      downloadUrl: 'https://example.com/a.apk',
      source: UpdateSource.auto,
    );
    expect(list.single.toString(), 'https://example.com/a.apk');
  });

  test('地址不可用时不产生候选', () {
    expect(
      UpdateSources.candidates(downloadUrl: '', source: UpdateSource.auto),
      isEmpty,
    );
  });
}
