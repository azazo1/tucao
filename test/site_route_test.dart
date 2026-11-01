import 'package:flutter_test/flutter_test.dart';
import 'package:tucao/common/constants.dart';
import 'package:tucao/utils/site_route.dart';

void main() {
  test('档案播放页地址解析为档案详情', () {
    final uri = parseSiteUrlInput('https://${Constants.host}/play/d7120/');
    expect(uri, isNotNull);
    final route = siteRouteOf(uri!);
    expect(route?.kind, SiteRouteKind.article);
    expect(route?.id, '7120');
    expect(route?.part, isNull);
    // 结尾省略斜杠也认.
    final noSlash = parseSiteUrlInput(
      'https://${Constants.host}/play/d7120',
    );
    expect(siteRouteOf(noSlash!)?.id, '7120');
  });

  test('视频地址解析分P锚点, 站点从 1 开始编号', () {
    SiteRoute? route(String raw) {
      final uri = parseSiteUrlInput(raw);
      expect(uri, isNotNull, reason: raw);
      return siteRouteOf(uri!);
    }

    final base = 'https://${Constants.host}/play/h4107869/';
    expect(route(base)?.kind, SiteRouteKind.video);
    expect(route(base)?.id, '4107869');
    expect(route(base)?.part, isNull);
    expect(route('$base#1')?.part, 0);
    expect(route('$base#3')?.part, 2);
    // 不合法的锚点按第一集处理, 不把分P带成负数的上一集.
    expect(route('$base#0')?.part, isNull);
    expect(route('$base#abc')?.part, isNull);
  });

  test('省略协议, 子域名与大小写都能识别', () {
    for (final raw in [
      '${Constants.host}/play/u82749/',
      'https://m.tucao.my/play/u82749/',
      'https://tucao.my/play/u82749/',
      'HTTPS://${Constants.host.toUpperCase()}/play/u82749/',
      '  https://${Constants.host}/play/u82749/?from=browser  ',
    ]) {
      final uri = parseSiteUrlInput(raw);
      expect(uri, isNotNull, reason: raw);
      final route = siteRouteOf(uri!);
      expect(route?.kind, SiteRouteKind.space, reason: raw);
      expect(route?.id, '82749', reason: raw);
    }
  });

  test('站外地址与普通关键词不当作站点地址', () {
    for (final raw in [
      'https://evil.example/play/d1/',
      'https://tucao.my.evil.example/play/d1/',
      'javascript:alert(1)',
      '播放页',
      'play/h4107869/',
      'https://',
      '',
    ]) {
      expect(parseSiteUrlInput(raw), isNull, reason: raw);
    }
  });

  test('站点没有对应页面的地址解析为空目标', () {
    final uri = parseSiteUrlInput('https://${Constants.host}/data/');
    expect(uri, isNotNull);
    expect(siteRouteOf(uri!), isNull);
    for (final path in ['/play/h/', '/play/x123/', '/play/h123/4.html']) {
      expect(
        siteRouteOf(Uri.parse('https://${Constants.host}$path')),
        isNull,
        reason: path,
      );
    }
  });

  test('空编号与全 0 编号不生成目标', () {
    for (final path in ['/play/h0/', '/play/h000/', '/play/d0/', '/play/u0/']) {
      expect(
        siteRouteOf(Uri.parse('https://${Constants.host}$path')),
        isNull,
        reason: path,
      );
    }
  });
}
