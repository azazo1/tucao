import 'package:dio/dio.dart';

/// 把异常翻译成能给用户看的一句话.
String errorText(Object error) {
  if (error is DioException) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return '网络超时, 请检查网络后重试';
      case DioExceptionType.connectionError:
        return '连接不上服务器, 请检查网络';
      case DioExceptionType.badCertificate:
        return '证书校验失败';
      case DioExceptionType.cancel:
        return '请求已取消';
      case DioExceptionType.badResponse:
        final code = error.response?.statusCode;
        return code == null ? '服务器返回异常' : '服务器返回 $code';
      case DioExceptionType.unknown:
        break;
    }
  }
  final message = error is Exception
      ? error.toString().replaceFirst('Exception: ', '')
      : '$error';
  return message.trim().isEmpty ? '操作失败' : message.trim();
}
