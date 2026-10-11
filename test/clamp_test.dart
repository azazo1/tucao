import 'package:flutter_test/flutter_test.dart';

/// 分组下标 clamp 的边界测试.
///
/// Dart 的 num.clamp 要求下界不大于上界, 列表为空时
/// `index.clamp(0, length - 1)` 等于 `clamp(0, -1)`, 会直接抛
/// Invalid argument(s). 这类写法在分组为空 (接口失败或站点改版)
/// 时会让界面崩掉, 因此这里把边界行为固定下来.
void main() {
  group('分组下标 clamp', () {
    test('空列表时 clamp 会抛异常', () {
      const groups = <int>[];
      expect(
        () => 0.clamp(0, groups.length - 1),
        throwsArgumentError,
      );
    });

    test('非空列表时下标被夹到合法范围', () {
      const groups = [1, 2, 3];
      expect(5.clamp(0, groups.length - 1), 2);
      expect((-1).clamp(0, groups.length - 1), 0);
      expect(1.clamp(0, groups.length - 1), 1);
    });

    test('先判空再取下标是安全的写法', () {
      const groups = <int>[];
      int? picked;
      if (groups.isNotEmpty) {
        picked = groups[0.clamp(0, groups.length - 1)];
      }
      expect(picked, isNull);
    });
  });
}
