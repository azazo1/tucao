import 'package:flutter_test/flutter_test.dart';
import 'package:tucao/common/site_host.dart';

void main() {
  tearDown(() => SiteHost.setOverride(null));

  group('主站域名整理', () {
    test('去协议, 路径, 空白与大小写', () {
      expect(SiteHost.normalize('https://WWW.TUCAO.MY/'), 'www.tucao.my');
      expect(SiteHost.normalize('  www.tucao.my  '), 'www.tucao.my');
      expect(SiteHost.normalize('www.tucao.my/path'), 'www.tucao.my');
      expect(SiteHost.normalize('tucao.my:8443'), 'tucao.my:8443');
    });

    test('拒绝非法输入', () {
      expect(SiteHost.normalize(''), isNull);
      expect(SiteHost.normalize('localhost'), isNull);
      expect(SiteHost.normalize('bad_host.example'), isNull);
      expect(SiteHost.normalize('www.tucao.my:99999'), isNull);
      expect(SiteHost.normalize('www..tucao.my'), isNull);
    });
  });

  group('运行期覆盖', () {
    test('设置后地址跟随, 清空后回到默认', () {
      SiteHost.setOverride('tucao.my');
      expect(SiteHost.host, 'tucao.my');
      expect(SiteHost.baseUrl, 'https://tucao.my/');

      SiteHost.setOverride(null);
      expect(SiteHost.host, SiteHost.defaultHost);
      expect(SiteHost.baseUrl, 'https://${SiteHost.defaultHost}/');
    });

    test('非法值不覆盖当前域名', () {
      SiteHost.setOverride('tucao.my');
      SiteHost.setOverride('bad_host');
      expect(SiteHost.host, 'tucao.my');
    });
  });
}
