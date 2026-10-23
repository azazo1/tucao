import 'package:tucao/models/video.dart';

/// 本地屏蔽记录.
///
/// 只保存展示需要的最小字段, 解除屏蔽后条目会从站点数据里重新出现,
/// 不依赖这条记录还原视频详情.
class BlockedVideo {
  const BlockedVideo({
    required this.hid,
    required this.title,
    this.cover = '',
    this.typeName = '',
    required this.blockedAt,
  });

  /// 视频编号, 与列表条目对应.
  final String hid;

  final String title;
  final String cover;

  /// 分区名, 番剧通常是连载新番一类的名字.
  final String typeName;

  /// 屏蔽时间, 秒级时间戳.
  final int blockedAt;

  factory BlockedVideo.fromVideo(VideoModel video) => BlockedVideo(
    hid: video.hid,
    title: video.title,
    cover: video.cover,
    typeName: video.typeName,
    blockedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
  );

  Map<String, dynamic> toJson() => {
    'hid': hid,
    'title': title,
    'cover': cover,
    'typeName': typeName,
    'blockedAt': blockedAt,
  };

  factory BlockedVideo.fromJson(Map<String, dynamic> json) {
    final hid = json['hid']?.toString() ?? '';
    if (!RegExp(r'^[0-9]+$').hasMatch(hid)) {
      throw const FormatException('屏蔽记录的视频 id 无效');
    }
    final title = json['title']?.toString() ?? '';
    final blockedAt = json['blockedAt'];
    return BlockedVideo(
      hid: hid,
      title: title.isEmpty ? '视频 $hid' : title,
      cover: json['cover']?.toString() ?? '',
      typeName: json['typeName']?.toString() ?? '',
      blockedAt: blockedAt is int ? blockedAt : 0,
    );
  }
}
