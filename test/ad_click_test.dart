import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tucao/http/ad_http.dart';
import 'package:tucao/utils/http_util.dart';

class _Adapter implements HttpClientAdapter {
  String body = '1';
  int status = 200;
  bool fail = false;
  RequestOptions? request;

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    request = options;
    if (fail) throw DioException(requestOptions: options,
        type: DioExceptionType.connectionError);
    return ResponseBody.fromString(body, status);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late _Adapter adapter;
  setUpAll(HttpUtil.init);
  setUp(() {
    adapter = _Adapter();
    HttpUtil.dio.httpClientAdapter = adapter;
  });

  test('只将明确的肯定响应作为感谢触发条件, 保留广告位和时间戳', () async {
    expect(await AdHttp.reportClick('t36'), isTrue);
    final request = adapter.request!;
    expect(request.method, 'GET');
    expect(request.uri.queryParameters['adid'], 't36');
    expect(int.tryParse(request.uri.queryParameters['t']!), isNotNull);
    for (final body in ['0', '', '<html>login</html>', 'unknown']) {
      adapter.body = body;
      expect(await AdHttp.reportClick('t36'), isFalse);
    }
    adapter.body = '1';
    adapter.status = 403;
    expect(await AdHttp.reportClick('t36'), isFalse);
    adapter.fail = true;
    expect(await AdHttp.reportClick('t36'), isFalse);
  });
}
