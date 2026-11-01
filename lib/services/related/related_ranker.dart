import 'package:tucao/models/video.dart';
import 'package:tucao/services/related/series_parser.dart';

/// 相关视频列表里的一项.
class RelatedEntry {
  const RelatedEntry({
    required this.video,
    required this.series,
    required this.sameSeries,
  });

  final VideoModel video;
  final SeriesInfo series;

  /// 标题里含有当前作品名, 判定为同一系列.
  final bool sameSeries;

  /// 封面角标, 只给同系列条目标季数, 其余条目的季数与当前作品无关.
  String? get label => sameSeries ? series.label : null;
}

/// 把搜索召回的候选去重并排序.
///
/// 同一季的多个整季投稿全部保留, 单集投稿收起. 同系列条目按
/// 类型, 季序, 前后篇排列, 同一位置按播放数从高到低;
/// 其余条目排在后面, 按播放数从高到低.
abstract final class RelatedRanker {
  static List<RelatedEntry> rank(
    VideoModel current,
    Iterable<VideoModel> candidates,
  ) {
    final aliasKeys = [
      for (final alias in SeriesParser.parseAliases(current.title))
        SeriesParser.normalizeKey(alias),
    ].where((key) => key.isNotEmpty).toList();

    final seen = <String>{current.hid};
    final entries = <RelatedEntry>[];
    for (final video in candidates) {
      if (video.hid.isEmpty || !seen.add(video.hid)) {
        continue;
      }
      final titleKey = SeriesParser.normalizeKey(video.title);
      entries.add(
        RelatedEntry(
          video: video,
          series: SeriesParser.parse(video.title, typeId: video.typeId),
          sameSeries: aliasKeys.any(titleKey.contains),
        ),
      );
    }
    entries.sort(_compare);
    return _collapseEpisodes(entries);
  }

  /// 收起单集投稿.
  ///
  /// 同一作品同一季有整季投稿时, 单集全部去掉; 只有单集时,
  /// 留集数最小的一条作为这一季的入口. 整季投稿全部保留.
  static List<RelatedEntry> _collapseEpisodes(List<RelatedEntry> sorted) {
    final hasWhole = <String>{};
    final firstEpisode = <String, RelatedEntry>{};
    for (final entry in sorted) {
      final key = _seasonKey(entry);
      if (!entry.series.isEpisode) {
        hasWhole.add(key);
        continue;
      }
      final kept = firstEpisode[key];
      if (kept == null || entry.series.episode! < kept.series.episode!) {
        firstEpisode[key] = entry;
      }
    }
    return [
      for (final entry in sorted)
        if (!entry.series.isEpisode ||
            (!hasWhole.contains(_seasonKey(entry)) &&
                identical(firstEpisode[_seasonKey(entry)], entry)))
          entry,
    ];
  }

  /// 同一作品同一季的分组键.
  static String _seasonKey(RelatedEntry entry) {
    final series = entry.series;
    final name = series.aliases.isEmpty
        ? entry.video.title
        : SeriesParser.normalizeKey(series.aliases.first);
    return '$name|${series.kind.name}|${series.seasonOrder}|${series.part ?? 0}';
  }

  static int _compare(RelatedEntry a, RelatedEntry b) {
    if (a.sameSeries != b.sameSeries) {
      return a.sameSeries ? -1 : 1;
    }
    if (a.sameSeries) {
      final byKind = a.series.kind.index.compareTo(b.series.kind.index);
      if (byKind != 0) {
        return byKind;
      }
      final bySeason = a.series.seasonOrder.compareTo(b.series.seasonOrder);
      if (bySeason != 0) {
        return bySeason;
      }
      final byPart = (a.series.part ?? 0).compareTo(b.series.part ?? 0);
      if (byPart != 0) {
        return byPart;
      }
    }
    final byPlay = b.video.playCount.compareTo(a.video.playCount);
    if (byPlay != 0) {
      return byPlay;
    }
    // sort 不稳定, 用 hid 兜底让顺序可复现.
    return a.video.hid.compareTo(b.video.hid);
  }
}
