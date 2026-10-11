import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:tucao/common/constants.dart';
import 'package:tucao/utils/logger.dart';

/// 统一的请求客户端.
///
/// 站点接口对 UA 与 cookie 都有依赖, 登录态通过 cookie 维持,
/// 因此这里统一挂载 UA, referer 与响应日志拦截器.
class HttpUtil {
  HttpUtil._();

  static late final Dio dio;

  static void init({Interceptor? cookieInterceptor}) {
    dio = Dio(
      BaseOptions(
        baseUrl: Constants.baseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 20),
        sendTimeout: const Duration(seconds: 10),
        headers: {
          'user-agent': Constants.userAgent,
          'referer': Constants.baseUrl,
        },
        // 站点接口的 code 字段并不等于 HTTP 状态码, 因此不对状态码做额外限制.
        validateStatus: (status) => status != null && status < 500,
        responseType: ResponseType.plain,
      ),
    );
    if (cookieInterceptor != null) {
      dio.interceptors.add(cookieInterceptor);
    }
    dio.interceptors.add(_LogInterceptor());
  }

  /// 站点接口并不总是返回合法 json, 这里做一次宽松解析.
  static Map<String, dynamic> decodeJson(String raw) {
    final text = raw.trim();
    if (text.isEmpty) {
      throw FormatException('接口返回内容为空');
    }
    final decoded = jsonDecode(text);
    if (decoded is! Map) {
      throw FormatException('接口返回内容不是对象: ${text.substring(0, text.length.clamp(0, 120))}');
    }
    return decoded.cast<String, dynamic>();
  }
}

/// cookie 拦截器的抽象, 便于在初始化顺序上解耦.
abstract class CookieInterceptor extends Interceptor {}

class _LogInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    Log.d('请求 ${options.method} ${options.uri}');
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final raw = response.data?.toString() ?? '';
    Log.d(
      '响应 ${response.statusCode} ${response.requestOptions.uri} '
      '长度=${raw.length}',
    );
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    Log.e(
      '请求失败 ${err.requestOptions.uri}',
      error: err,
      stackTrace: err.stackTrace,
    );
    handler.next(err);
  }
}
