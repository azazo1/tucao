import 'package:tucao/models/video.dart';

/// 本地收藏记录, 与官方客户端一样按 hid 去重, 不随账号同步.
class FavoriteItem {
  const FavoriteItem({required this.video, required this.savedAt});

  final VideoModel video;
  final int savedAt;

  Map<String, dynamic> toJson() => {
    'savedAt': savedAt,
    'video': {
      'hid': video.hid,
      'title': video.title,
      'typeid': video.typeId,
      'typename': video.typeName,
      'thumb': video.cover,
      'play': video.playCount,
      'mukio': video.danmakuCount,
      'create': video.createTime,
      'description': video.description,
      'keywords': video.keywords,
      'user': video.userName,
      'userid': video.userId,
      'part': video.partCount,
      'url': video.url,
    },
  };

  factory FavoriteItem.fromJson(Map<String, dynamic> json) {
    final rawVideo = json['video'];
    if (rawVideo is! Map || json['savedAt'] is! int) {
      throw const FormatException('本地收藏记录格式无效');
    }
    final video = VideoModel.fromJson(rawVideo.cast<String, dynamic>());
    if (!RegExp(r'^[0-9]+$').hasMatch(video.hid)) {
      throw const FormatException('本地收藏视频 id 无效');
    }
    return FavoriteItem(video: video, savedAt: json['savedAt'] as int);
  }
}
