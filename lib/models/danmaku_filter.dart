import 'package:tucao/models/danmaku.dart';

/// 弹幕屏蔽词与重复合并设置, 独立于弹幕样式单独存储和升级.
class DanmakuFilter {
  const DanmakuFilter({this.keywords = const [], this.mergeDuplicates = true});

  static const version = 1;
  static const defaults = DanmakuFilter();

  /// 单条屏蔽词的长度上限, 防止误粘贴一大段文字.
  static const maxKeywordLength = 60;

  /// 相同内容在这个时间窗口内只保留第一条.
  static const mergeWindowSeconds = 10.0;

  /// 合并条数达到这个值才在弹幕后标注数量, 两三条重复不值得提示.
  static const mergeMarkThreshold = 3;

  /// 屏蔽词, 包含即屏蔽, 不区分大小写. 用 `/` 包起来的按正则匹配.
  final List<String> keywords;

  /// 合并短时间内内容相同的弹幕.
  final bool mergeDuplicates;

  bool get isEmpty => keywords.isEmpty && !mergeDuplicates;

  /// 规整屏蔽词: 去掉首尾空白, 丢弃空项与超长项, 去重并保持原顺序.
  static List<String> normalizeKeywords(Iterable<Object?> raw) {
    final result = <String>[];
    final seen = <String>{};
    for (final item in raw) {
      if (item is! String) continue;
      final value = item.trim();
      if (value.isEmpty || value.length > maxKeywordLength) continue;
      if (seen.add(value)) result.add(value);
    }
    return result;
  }

  /// 以 `/` 开头和结尾且中间非空的屏蔽词按正则处理.
  static bool isRegex(String keyword) =>
      keyword.length > 2 && keyword.startsWith('/') && keyword.endsWith('/');

  /// 正则屏蔽词是否能编译, 普通屏蔽词总是有效.
  static bool isValidKeyword(String keyword) {
    if (!isRegex(keyword)) return true;
    try {
      RegExp(keyword.substring(1, keyword.length - 1));
      return true;
    } on FormatException {
      return false;
    }
  }

  factory DanmakuFilter.fromMap(Map map) {
    final keywords = map['keywords'];
    final merge = map['mergeDuplicates'];
    return DanmakuFilter(
      keywords: keywords is List ? normalizeKeywords(keywords) : const [],
      mergeDuplicates: merge is bool ? merge : true,
    );
  }

  Map<String, Object?> toMap() => {
    'version': version,
    'keywords': keywords,
    'mergeDuplicates': mergeDuplicates,
  };

  DanmakuFilter copyWith({List<String>? keywords, bool? mergeDuplicates}) =>
      DanmakuFilter(
        keywords: keywords == null
            ? this.keywords
            : normalizeKeywords(keywords),
        mergeDuplicates: mergeDuplicates ?? this.mergeDuplicates,
      );

  /// 对按时间排好序的弹幕做屏蔽和合并, 返回新列表.
  ///
  /// 合并时保留同一内容在窗口内的第一条, 被合并的条数达到
  /// [mergeMarkThreshold] 时在文字后标注总数. 无效正则直接忽略.
  List<DanmakuModel> apply(List<DanmakuModel> sorted) {
    if (isEmpty) return sorted;
    final plain = <String>[];
    final patterns = <RegExp>[];
    for (final keyword in keywords) {
      if (isRegex(keyword)) {
        try {
          patterns.add(
            RegExp(
              keyword.substring(1, keyword.length - 1),
              caseSensitive: false,
            ),
          );
        } on FormatException {
          continue;
        }
      } else {
        plain.add(keyword.toLowerCase());
      }
    }
    bool blocked(String text) {
      final lower = text.toLowerCase();
      return plain.any(lower.contains) || patterns.any((p) => p.hasMatch(text));
    }

    final kept = <DanmakuModel>[];
    // 内容到它在 kept 里的下标和累计条数, 只在合并时使用.
    final lastIndex = <String, int>{};
    final counts = <int, int>{};
    for (final item in sorted) {
      final text = item.text.trim();
      if (text.isEmpty || blocked(text)) continue;
      if (mergeDuplicates) {
        final index = lastIndex[text];
        if (index != null &&
            item.time - kept[index].time <= mergeWindowSeconds) {
          counts[index] = (counts[index] ?? 1) + 1;
          continue;
        }
        lastIndex[text] = kept.length;
      }
      kept.add(item);
    }
    for (final entry in counts.entries) {
      if (entry.value < mergeMarkThreshold) continue;
      final item = kept[entry.key];
      kept[entry.key] = DanmakuModel(
        time: item.time,
        mode: item.mode,
        fontSize: item.fontSize,
        color: item.color,
        timestamp: item.timestamp,
        text: '${item.text} ×${entry.value}',
      );
    }
    return kept;
  }
}
