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

  test('域名对不上时按路径识别站内页面', () {
    for (final raw in [
      'https://tucao.new-domain.example/play/h4107869/#2',
      'new-domain.example/play/h4107869/',
      'http://1.2.3.4:8080/play/h4107869',
    ]) {
      final uri = parseSiteUrlInput(raw);
      expect(uri, isNotNull, reason: raw);
      final route = siteRouteOf(uri!);
      expect(route?.kind, SiteRouteKind.video, reason: raw);
      expect(route?.id, '4107869', reason: raw);
    }
  });

  test('站外地址与普通关键词不当作站点地址', () {
    for (final raw in [
      // 域名对不上且路径不是站内页面时不认.
      'https://evil.example/data/',
      'https://evil.example/play/h0/',
      'ftp://evil.example/play/h1/',
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

  test('搜索栏输入的站内编号直接解析为页面', () {
    void expectRoute(String raw, SiteRouteKind kind, String id, [int? part]) {
      final route = parseSiteIdInput(raw);
      expect(route?.kind, kind, reason: raw);
      expect(route?.id, id, reason: raw);
      expect(route?.part, part, reason: raw);
    }

    for (final raw in [
      'h4070523',
      'H4070523',
      ' h4070523/ ',
      'play/h4070523/',
      '/play/h4070523',
      'ｈ４０７０５２３',
      '4070523',
    ]) {
      expectRoute(raw, SiteRouteKind.video, '4070523');
    }
    expectRoute('h4070523#2', SiteRouteKind.video, '4070523', 1);
    expectRoute('h4070523/#3', SiteRouteKind.video, '4070523', 2);
    expectRoute('h4070523#0', SiteRouteKind.video, '4070523');
    expectRoute('d7120', SiteRouteKind.article, '7120');
    expectRoute('U82749', SiteRouteKind.space, '82749');
    // 带 play/ 时就是站点路径, 不限位数.
    expectRoute('play/h12/', SiteRouteKind.video, '12');
  });

  test('编码名, 年份与普通关键词不当作站内编号', () {
    for (final raw in [
      'h264',
      'H265',
      'u2',
      '2024',
      '1080',
      'h0000',
      '0000000',
      'h4070523 第二集',
      'x4070523',
      '出包王女',
      '',
    ]) {
      expect(parseSiteIdInput(raw), isNull, reason: raw);
    }
  });

  test('分享文案里夹带的站点链接能被找出来', () {
    final route = findSiteRouteInText(
      '【无修】To LOVE 出包王女 全四季 https://www.tucao.my/play/h4070523/#2，快来看',
    );
    expect(route?.kind, SiteRouteKind.video);
    expect(route?.id, '4070523');
    expect(route?.part, 1);
    expect(
      findSiteRouteInText('看这个 (https://tucao.my/play/d7120/).')?.id,
      '7120',
    );
    // 只有站外链接或者没有链接时不处理, 交给关键词搜索.
    expect(findSiteRouteInText('https://evil.example/data/ 出包王女'), isNull);
    expect(findSiteRouteInText('出包王女 第四季'), isNull);
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
