/// 站点通用的接口响应包装.
///
/// 站点接口的 code 字段并不总是数字, 有的接口返回 "200", 有的返回 "400",
/// 因此这里统一按字符串解析.
class ApiResponse<T> {
  const ApiResponse({required this.code, this.message, this.result});

  final String code;
  final String? message;
  final T? result;

  bool get success => code == '200';

  factory ApiResponse.fromJson(
    Map<String, dynamic> json,
    T Function(dynamic data) parse,
  ) {
    final rawCode = json['code'];
    return ApiResponse<T>(
      code: rawCode?.toString() ?? '',
      message: json['msg']?.toString(),
      result: json['result'] == null ? null : parse(json['result']),
    );
  }
}

/// 带总数的列表响应.
class ListResponse<T> {
  const ListResponse({
    required this.code,
    required this.total,
    this.message,
    this.list = const [],
  });

  final String code;
  final String? message;
  final int total;
  final List<T> list;

  bool get success => code == '200';

  factory ListResponse.fromJson(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic> data) parse,
  ) {
    final rawList = json['result'];
    return ListResponse<T>(
      code: json['code']?.toString() ?? '',
      message: json['msg']?.toString(),
      total: int.tryParse(json['total_count']?.toString() ?? '') ?? 0,
      list: rawList is List
          ? rawList
                .whereType<Map>()
                .map((e) => parse(e.cast<String, dynamic>()))
                .toList()
          : const [],
    );
  }
}

/// 接口返回的异常.
class ApiException implements Exception {
  ApiException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => message;
}
