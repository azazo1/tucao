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
}
