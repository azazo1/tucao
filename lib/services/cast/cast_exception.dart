/// 投屏过程中的可读错误.
class CastException implements Exception {
  const CastException(this.message);

  final String message;

  @override
  String toString() => message;
}
