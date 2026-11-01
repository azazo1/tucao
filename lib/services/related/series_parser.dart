/// 从视频标题里猜系列信息.
///
/// 站点没有结构化的季字段, 标题大多写成 `【标签】作品名 别名 第二季【字幕组】`,
/// 这里只靠规则猜作品名, 季数与类型. 猜不准时宁可少标, 条目照样出现在列表里.
library;

/// 条目类型, 声明顺序就是相关视频列表里同系列条目的先后.
enum SeriesKind { tv, recap, movie, ova, spinoff, live }

/// 一个标题里能猜出的系列信息.
class SeriesInfo {
  const SeriesInfo({
    required this.aliases,
    required this.kind,
    this.season,
    this.part,
    this.episode,
  });

  /// 作品名, 第一项是主名, 后面是别名, 最多 [SeriesParser.aliasLimit] 个.
  final List<String> aliases;

  final SeriesKind kind;

  /// 季序号, 最终季记为 [SeriesParser.finalSeason], 标题里没写时为空.
  final int? season;

  /// 同一季的前后篇, 1 为前篇, 2 为后篇.
  final int? part;

  /// 单集投稿的集数, 合集与整季投稿为空.
  final int? episode;

  /// 是否为一眼能看出的单集投稿.
  bool get isEpisode => episode != null;

  /// 排序用的季序号, 没写季数的正篇按第一季算.
  int get seasonOrder => season ?? 1;

  /// 封面角标, 猜不出时为空.
  String? get label {
    final base = switch (kind) {
      SeriesKind.recap => '总集篇',
      SeriesKind.movie => '剧场版',
      SeriesKind.ova => 'OVA',
      SeriesKind.spinoff => '外传',
      SeriesKind.live => '真人',
      SeriesKind.tv => switch (season) {
        null => null,
        SeriesParser.finalSeason => '最终季',
        final value => '第$value季',
      },
    };
    final half = switch (part) {
      1 => '前篇',
      2 => '后篇',
      _ => null,
    };
    if (base == null) {
      return half;
    }
    return half == null ? base : '$base $half';
  }
}

abstract final class SeriesParser {
  /// 最多保留的作品名个数, 每个名字都会单独发起搜索.
  static const aliasLimit = 3;

  /// 最终季的季序号, 排在所有写了数字的季之后.
  static const finalSeason = 99;

  /// 影剧分区下的电视剧与电影, 这里的条目都按真人版处理.
  static const liveTypeIds = {38, 39};

  /// 剧场版分区.
  static const movieTypeId = 26;

  /// 完结番组分区.
  static const tvCollectionTypeId = 10;

  static final _brackets = RegExp(
    r'【[^】]*】|『[^』]*』|〖[^〗]*〗|\[[^\]]*\]|［[^］]*］',
  );

  /// 包着作品名或副标题的引号, 先换成空格, 不能连同内容一起丢掉.
  static final _quotes = RegExp(r'[《》「」“”"]');

  static final _seasonNumber = RegExp(
    r'第\s*([0-9]{1,2}|[一二三四五六七八九十]{1,3})\s*[季期部]'
    r'|(?<![a-z0-9])(?:season\s*|s)([0-9]{1,2})(?![0-9a-z])',
    caseSensitive: false,
  );

  static final _finalSeason = RegExp(
    r'最终季|最終季|最终章|final\s*season',
    caseSensitive: false,
  );

  static final _part = RegExp(
    r'前篇|前编|前編|上篇|上半|前半|part\s*1(?![0-9])'
    r'|(?<!前)(?:后篇|後篇|后编|後編)|下篇|下半|后半|後半|part\s*2(?![0-9])',
    caseSensitive: false,
  );

  static final _frontPart = RegExp(r'^(?:前|上|part\s*1)', caseSensitive: false);

  static final _movie = RegExp(
    r'剧场版|劇場版|映画|电影版|(?<![a-z])movie(?![a-z])',
    caseSensitive: false,
  );

  static final _ova = RegExp(
    r'(?<![a-z])(?:ova|oad)(?![a-z])',
    caseSensitive: false,
  );

  static final _recap = RegExp(r'总集篇|總集篇|新编集版|新編集版');

  static final _spinoff = RegExp(r'外传|外傳|番外');

  /// 作品名到这里为止, 后面是季数, 集数, 画质或者篇名.
  static final _cut = RegExp(
    r'第\s*[0-9一二三四五六七八九十]+\s*[季期部集话話卷章]'
    r'|(?<![a-z0-9])(?:season\s*|s)[0-9]{1,2}(?![0-9a-z])'
    r'|最终季|最終季|最终章|final\s*season'
    r'|剧场版|劇場版|映画|电影版|(?<![a-z])(?:ova|oad)(?![a-z])'
    r'|外传|外傳|番外|总集篇|總集篇|新编集版|新編集版|特别篇'
    r'|(?<![a-z])(?:bd|web|tv)\s*rip|(?<![0-9])[0-9]{3,4}p(?![a-z])'
    r'|(?<![0-9])[0-9]{1,3}\s*[-~～]\s*[0-9]{1,3}'
    r'|全[0-9一二三四五六七八九十]+[季集话話]|全集|合集'
    r'|\s[0-9]{1,3}(?=\s|$)'
    r'|\s\S{1,8}篇(?=\s|$)',
    caseSensitive: false,
  );

  /// 合集特征: 集数范围, 合集, 全集, 全 N 话. `第14-15集` 这种双集连发不算.
  static final _collection = RegExp(
    r'(?<![0-9第])[0-9]{1,3}\s*[-~～]\s*[0-9]{1,3}(?![0-9])'
    r'|合集|全集|全[0-9一二三四五六七八九十]+[季集话話]',
  );

  /// 带单位的集数, 比如 `第05集`, `13话`.
  static final _markedEpisode = RegExp(r'第?\s*([0-9]{1,3})\s*[集话話]');

  /// 方括号外独立的数字, 比如 `间谍过家家 22`.
  static final _bareEpisode = RegExp(r'(?:^|\s)([0-9]{1,3})(?=\s|$)');

  static final _separator = RegExp(r'[/／|｜()（）~～:：,，、+＋&＆]');

  static final _edgePunct = RegExp(r'^[\s.\-_·•!！?？]+|[\s.\-_·•!！?？]+$');

  static final _cjk = RegExp(r'[\u3040-\u30ff\u3400-\u9fff]');

  /// 解析一个标题. [typeId] 用来补充类型判断, 不知道时传 0.
  static SeriesInfo parse(String title, {int typeId = 0}) {
    final season = _parseSeason(title);
    final outside = title.replaceAll(_brackets, ' ');
    return SeriesInfo(
      aliases: parseAliases(title),
      kind: _parseKind(
        title,
        outside,
        typeId: typeId,
        hasSeason: season != null,
      ),
      season: season,
      part: _parsePart(title),
      episode: _parseEpisode(title, outside, typeId: typeId),
    );
  }

  /// 单集投稿的集数. 完结番组分区与带合集特征的标题都按整季处理.
  static int? _parseEpisode(
    String title,
    String outside, {
    required int typeId,
  }) {
    if (typeId == tvCollectionTypeId || _collection.hasMatch(title)) {
      return null;
    }
    final match =
        _markedEpisode.firstMatch(title) ?? _bareEpisode.firstMatch(outside);
    final value = int.tryParse(match?.group(1) ?? '');
    return value == null || value <= 0 ? null : value;
  }

  /// 从标题里取出作品名与别名.
  static List<String> parseAliases(String title) {
    var text = title.replaceAll(_brackets, ' ').replaceAll(_quotes, ' ').trim();
    // 标记在开头时去掉它接着找, 比如 `剧场版 咒术回战 0`.
    for (var i = 0; i < 4; i++) {
      final match = _cut.firstMatch(text);
      if (match == null) {
        break;
      }
      if (match.start == 0) {
        text = text.substring(match.end).trim();
        continue;
      }
      text = text.substring(0, match.start).trim();
      break;
    }

    final aliases = <String>[];
    final keys = <String>{};
    for (final segment in text.split(_separator)) {
      for (final candidate in _splitScripts(segment)) {
        final alias = candidate.replaceAll(_edgePunct, '');
        final key = normalizeKey(alias);
        if (!_isUsable(alias, key) || !keys.add(key)) {
          continue;
        }
        aliases.add(alias);
        if (aliases.length >= aliasLimit) {
          return aliases;
        }
      }
    }
    return aliases;
  }

  /// 比较用的键: 小写, 全角转半角, 只留字母数字与中日文字符.
  static String normalizeKey(String raw) {
    final buffer = StringBuffer();
    for (var code in raw.runes) {
      if (code >= 0xFF01 && code <= 0xFF5E) {
        code -= 0xFEE0;
      }
      if (code >= 0x41 && code <= 0x5A) {
        code += 0x20;
      }
      final keep =
          (code >= 0x30 && code <= 0x39) ||
          (code >= 0x61 && code <= 0x7A) ||
          (code >= 0x3040 && code <= 0x30FF) ||
          (code >= 0x3400 && code <= 0x9FFF);
      if (keep) {
        buffer.writeCharCode(code);
      }
    }
    return buffer.toString();
  }

  /// 按空格拆开, 中文词各自成名, 相邻的英文词拼回一个名字.
  ///
  /// `缘之空 Yosuga no Sora` 拆成 `缘之空` 与 `Yosuga no Sora`.
  static List<String> _splitScripts(String segment) {
    final result = <String>[];
    final latin = <String>[];
    void flushLatin() {
      if (latin.isNotEmpty) {
        result.add(latin.join(' '));
        latin.clear();
      }
    }

    for (final token in segment.trim().split(RegExp(r'\s+'))) {
      if (token.isEmpty) {
        continue;
      }
      if (_cjk.hasMatch(token)) {
        flushLatin();
        result.add(token);
      } else {
        latin.add(token);
      }
    }
    flushLatin();
    return result;
  }

  /// 太短的名字搜出来全是噪声, 中文至少两个字, 纯英文至少四个字母数字.
  static bool _isUsable(String alias, String key) {
    final cjkCount = _cjk.allMatches(alias).length;
    if (cjkCount > 0) {
      return cjkCount >= 2;
    }
    return key.length >= 4;
  }

  static int? _parseSeason(String title) {
    if (_finalSeason.hasMatch(title)) {
      return finalSeason;
    }
    final match = _seasonNumber.firstMatch(title);
    if (match == null) {
      return null;
    }
    final raw = match.group(1) ?? match.group(2);
    final value = raw == null ? null : _parseNumber(raw);
    return value == null || value <= 0 ? null : value;
  }

  static int? _parsePart(String title) {
    final match = _part.firstMatch(title);
    if (match == null) {
      return null;
    }
    return _frontPart.hasMatch(match.group(0)!) ? 1 : 2;
  }

  /// 判断类型.
  ///
  /// 写了季数的, 以及完结番组分区里的都算正篇, 后者多是整季或全集合集,
  /// 标题里附带的 `+OAD+剧场版` 不改变类型. 外传类标记只看方括号外面,
  /// 合集标题里的 `【特别篇】` 只是附带内容.
  static SeriesKind _parseKind(
    String title,
    String outside, {
    required int typeId,
    required bool hasSeason,
  }) {
    if (liveTypeIds.contains(typeId)) {
      return SeriesKind.live;
    }
    if (hasSeason || typeId == tvCollectionTypeId) {
      return SeriesKind.tv;
    }
    if (_movie.hasMatch(title)) {
      return SeriesKind.movie;
    }
    if (_ova.hasMatch(title)) {
      return SeriesKind.ova;
    }
    if (_recap.hasMatch(outside)) {
      return SeriesKind.recap;
    }
    if (_spinoff.hasMatch(outside)) {
      return SeriesKind.spinoff;
    }
    if (typeId == movieTypeId) {
      return SeriesKind.movie;
    }
    return SeriesKind.tv;
  }

  static int? _parseNumber(String raw) {
    final value = int.tryParse(raw);
    if (value != null) {
      return value;
    }
    const digits = {
      '一': 1,
      '二': 2,
      '三': 3,
      '四': 4,
      '五': 5,
      '六': 6,
      '七': 7,
      '八': 8,
      '九': 9,
    };
    final ten = raw.indexOf('十');
    if (ten < 0) {
      return raw.length == 1 ? digits[raw] : null;
    }
    final high = ten == 0 ? 1 : digits[raw.substring(0, ten)];
    final lowRaw = raw.substring(ten + 1);
    final low = lowRaw.isEmpty ? 0 : digits[lowRaw];
    if (high == null || low == null) {
      return null;
    }
    return high * 10 + low;
  }
}
