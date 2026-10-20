import 'package:flutter_test/flutter_test.dart';
import 'package:tucao/common/constants.dart';
import 'package:tucao/utils/site_url.dart';

void main() {
  test('相对地址补成绝对地址', () {
    expect(
      absoluteSiteUrl('/uploadfile/2023/0823/a.jpg'),
      '${Constants.baseUrl}uploadfile/2023/0823/a.jpg',
    );
    expect(
      absoluteSiteUrl('uploadfile/2023/0823/a.jpg'),
      '${Constants.baseUrl}uploadfile/2023/0823/a.jpg',
    );
    expect(
      absoluteSiteUrl('https://www.tucao.my/a.jpg'),
      'https://www.tucao.my/a.jpg',
    );
    expect(absoluteSiteUrl('  '), isEmpty);
  });

  test('站外图片不被当成站点图片', () {
    // 站点自己的地址自动加载, 站外地址由界面等用户点击.
    expect(
      isSiteImage('${Constants.baseUrl}uploadfile/2023/0823/a.jpg'),
      isTrue,
    );
    expect(isSiteImage('https://tucao.my/uploadfile/a.jpg'), isTrue);
    expect(isSiteImage('https://cdn.tucao.my/uploadfile/a.jpg'), isTrue);
    expect(isSiteImage('https://evil.example/a.jpg'), isFalse);
    expect(isSiteImage('https://tucao.my.evil.example/a.jpg'), isFalse);
    expect(isSiteImage('javascript:alert(1)'), isFalse);
  });

  test('头像地址补版本参数绕开站点缓存', () {
    final stamp = dayStamp(DateTime(2026, 10, 21));
    expect(stamp, '20261021');
    final avatar = Uri.parse(
      avatarUrl(
        '/phpsso_server/uploadfile/avatar/47/6/123/180x180.jpg',
        now: DateTime(2026, 10, 21),
      ),
    );
    expect(
      avatar.path,
      '/phpsso_server/uploadfile/avatar/47/6/123/180x180.jpg',
    );
    expect(avatar.queryParameters[avatarRevisionParam], '20261021');
  });

  test('头像版本参数保留原有查询, 替换旧版本', () {
    final avatar = Uri.parse(
      avatarUrl(
        '${Constants.baseUrl}avatar/180x180.jpg'
        '?size=180&tag=a&tag=b&_avatar_v=99#preview',
        revision: '100',
      ),
    );
    expect(avatar.queryParametersAll, {
      'size': ['180'],
      'tag': ['a', 'b'],
      avatarRevisionParam: ['100'],
    });
    expect(avatar.fragment, 'preview');
  });

  test('空头像与站外头像不加版本参数', () {
    expect(avatarUrl(''), isEmpty);
    expect(avatarUrl('  '), isEmpty);
    expect(
      avatarUrl('https://evil.example/a.jpg', revision: '100'),
      'https://evil.example/a.jpg',
    );
  });
}
