import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tucao/http/favorite_http.dart';
import 'package:tucao/services/site_favorite_service.dart';
import 'package:tucao/utils/http_util.dart';

/// 追番夹的页面片段按站点真实返回裁剪, 只保留解析用得上的结构.
const _folderHtml = '''
<html><body><div class="mfav">
  <div class="item t0">
    <div class="l"><a href="/play/h4107860/" target="_blank"><img src="https://www.tucao.my/uploadfile/2026/1004/thumb.jpg"></a></div>
    <div class="r">
      <div class="c"><a href="/list/11/" target="_blank">连载新番</a></div>
      <div class="t"><a href="/play/h4107860/" target="_blank">至高之力</a></div>
      <div class="tt"><a target="_blank" href="/play/u30944/">永恒之光</a> · 2026-10-19</div>
      <div class="d">住在冲绳北部的东道明 </div>
      <div class="m"><a href="/index.php?m=member&c=index&a=favorite&id=229842">取消</a></div>
    </div>
    <div class="clear"></div>
  </div>
  <div class="item t0">
    <div class="l"><a href="/play/d7095/" target="_blank"><img src="https://www.tucao.my/uploadfile/thumb-d.jpg"></a></div>
    <div class="r">
      <div class="c"><a href="/list/38/" target="_blank">电影</a></div>
      <div class="t"><a href="/play/d7095/" target="_blank">某部电影</a></div>
      <div class="tt"><a target="_blank" href="/play/u1/">某人</a> · 2026-01-01</div>
      <div class="m"><a href="/index.php?m=member&c=index&a=favorite&id=100">取消</a></div>
    </div>
  </div>
</div></body></html>
''';

/// 没有追番时站点仍然返回追番夹容器, 只是里面是空的.
const _emptyFolderHtml =
    '<html><body><div class="mfav">\r\n</div></body></html>';

/// 登录失效时站点返回的是提示页, 不是追番夹.
const _loginHtml =
    '<html><body><a href="index.php?m=member&c=index&a=login">'
    '您的会话已过期，请重新登录。</a></body></html>';

class _Adapter implements HttpClientAdapter {
  String response = '';
  final queue = <String>[];
  int status = 200;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final raw = queue.isEmpty ? response : queue.removeAt(0);
    return ResponseBody.fromString(raw, status);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  group('追番夹解析', () {
    test('条目字段与取消记录号取自页面', () {
      final items = FavoriteHttp.parseFolder(_folderHtml);
      expect(items, hasLength(2));
      final item = items.first;
      expect(item.recordId, 229842);
      expect(item.hid, '4107860');
      expect(item.title, '至高之力');
      expect(item.typeName, '连载新番');
      expect(item.userName, '永恒之光');
      expect(item.savedDate, '2026-10-19');
      expect(item.cover, isNotEmpty);
      expect(item.isVideo, isTrue);
      expect(item.video?.hid, '4107860');
    });

    test('非视频内容没有视频编号, 应用里打不开', () {
      final item = FavoriteHttp.parseFolder(_folderHtml).last;
      expect(item.recordId, 100);
      expect(item.hid, isEmpty);
      expect(item.isVideo, isFalse);
      expect(item.video, isNull);
    });

    test('空追番夹是空列表而不是错误', () {
      expect(FavoriteHttp.parseFolder(_emptyFolderHtml), isEmpty);
    });

    test('登录提示页不能被当成空追番夹', () {
      expect(
        () => FavoriteHttp.parseFolder(_loginHtml),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('追番服务', () {
    late _Adapter adapter;

    setUpAll(() {
      HttpUtil.init();
    });

    setUp(() {
      adapter = _Adapter();
      HttpUtil.dio.httpClientAdapter = adapter;
    });

    test('整份拉取后能按视频编号判断是否已追番', () async {
      adapter.response = _folderHtml;
      final service = SiteFavoriteService();
      await service.refresh(force: true);

      expect(adapter.requests.single.uri.path, '/index.php');
      expect(adapter.requests.single.uri.queryParameters['a'], 'favorite');
      expect(service.loaded, isTrue);
      expect(service.error.value, isNull);
      expect(service.contains('4107860'), isTrue);
      expect(service.contains('7095'), isFalse);
      expect(service.list, hasLength(2));
    });

    test('登录失效时状态不可信, 原因可读', () async {
      adapter.response = _loginHtml;
      final service = SiteFavoriteService();
      await service.refresh(force: true);

      expect(service.loaded, isFalse);
      expect(service.contains('4107860'), isFalse);
      expect(service.error.value, contains('登录'));
    });

    test('取消追番走记录号, 成功后再拉一次列表', () async {
      adapter.response = _folderHtml;
      final service = SiteFavoriteService();
      await service.refresh(force: true);
      final item = service.find('4107860')!;

      adapter.queue
        ..add('<html><body>取消成功</body></html>')
        ..add('<html><body><div class="mfav"></div></body></html>');
      await service.remove(item);

      expect(adapter.requests[1].uri.queryParameters['id'], '229842');
      expect(adapter.requests[1].uri.queryParameters['a'], 'favorite');
      expect(service.contains('4107860'), isFalse);
      expect(service.list, isEmpty);
    });

    test('站点没真的删掉时按失败抛出', () async {
      adapter.response = _folderHtml;
      final service = SiteFavoriteService();
      await service.refresh(force: true);
      final item = service.find('4107860')!;

      adapter.response = _folderHtml;
      await expectLater(service.remove(item), throwsStateError);
      expect(service.contains('4107860'), isTrue);
    });
  });
}
