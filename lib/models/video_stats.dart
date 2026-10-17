/// 播放页统计条的数据.
///
/// 站点没有一次性返回全部统计的 json 接口, 各项分开获取,
/// 因此未取到的字段为空.
class VideoStats {
  const VideoStats({
    this.playCount,
    this.onlineCount,
    this.commentCount,
    this.favoriteCount,
  });

  /// 总播放量, 来自 `api.php?op=count` 的 `hits`.
  final int? playCount;

  /// 当前正在观看的人数, 来自 `ol.php` 的 `olThis`.
  final int? onlineCount;

  /// 评论总数, 来自评论接口的 `total`.
  final int? commentCount;

  /// 站点追番数, 来自 `api.php?op=count` 的 `fav`.
  final int? favoriteCount;

  VideoStats copyWith({
    int? playCount,
    int? onlineCount,
    int? commentCount,
    int? favoriteCount,
  }) {
    return VideoStats(
      playCount: playCount ?? this.playCount,
      onlineCount: onlineCount ?? this.onlineCount,
      commentCount: commentCount ?? this.commentCount,
      favoriteCount: favoriteCount ?? this.favoriteCount,
    );
  }
}
