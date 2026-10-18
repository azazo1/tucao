/// 版本号的解析与比较.
///
/// 版本号可能来自构建注入 (`v1.2.0`), 包信息 (`1.2.0`) 或 GitHub 标签
/// (`v1.2.0`), 比较时只取数字段, 前缀 `v` 与 `+` / `-` 之后的内容不参与.
abstract final class Version {
  /// 把版本号拆成数字段, 无法解析的段按 0 处理.
  static List<int> parse(String raw) {
    var text = raw.trim();
    if (text.startsWith('v') || text.startsWith('V')) {
      text = text.substring(1);
    }
    final cut = text.indexOf(RegExp(r'[+-]'));
    if (cut >= 0) {
      text = text.substring(0, cut);
    }
    if (text.isEmpty) {
      return const [];
    }
    return [
      for (final part in text.split('.'))
        int.tryParse(RegExp(r'^\d+').firstMatch(part)?.group(0) ?? '') ?? 0,
    ];
  }

  /// 比较两个版本号, [a] 比 [b] 新时返回正数, 相同返回 0, 更旧返回负数.
  static int compare(String a, String b) {
    final left = parse(a);
    final right = parse(b);
    final length = left.length > right.length ? left.length : right.length;
    for (var i = 0; i < length; i++) {
      final x = i < left.length ? left[i] : 0;
      final y = i < right.length ? right[i] : 0;
      if (x != y) {
        return x - y;
      }
    }
    return 0;
  }

  /// [candidate] 是否比 [current] 新.
  static bool isNewer({required String current, required String candidate}) =>
      compare(candidate, current) > 0;
}
