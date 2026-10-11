/// 视频分P信息.
///
/// 站点存在两代视频源:
/// - 自建源直接返回 `file` 直链.
/// - 早期第三方源只返回 `vid` 与平台名, 需要再请求播放地址接口换取直链.
class VideoPart {
  const VideoPart({
    this.file,
    this.vid,
    this.type,
    required this.title,
  });

  /// 直链地址, 仅自建源存在.
  final String? file;

  /// 第三方平台的视频 id, 仅早期投稿存在.
  final String? vid;

  /// 视频源类型, `video` 表示自建源.
  final String? type;

  final String title;

  bool get isThirdParty => file == null || file!.isEmpty;

  factory VideoPart.fromJson(Map<String, dynamic> json) {
    return VideoPart(
      file: json['file']?.toString(),
      vid: json['vid']?.toString(),
      type: json['type']?.toString(),
      title: json['title']?.toString() ?? '',
    );
  }
}

/// 视频条目, 同时用于列表页与详情页.
class VideoModel {
  const VideoModel({
    required this.hid,
    required this.title,
    this.typeId = 0,
    this.typeName = '',
    this.cover = '',
    this.playCount = 0,
    this.danmakuCount = 0,
    this.createTime = 0,
    this.description = '',
    this.keywords = '',
    this.userName = '',
    this.userId = 0,
    this.partCount = 0,
    this.url,
    this.parts = const [],
  });

  final String hid;
  final String title;
  final int typeId;
  final String typeName;
  final String cover;

  /// 播放数, 接口以字符串返回.
  final int playCount;

  /// 弹幕数.
  final int danmakuCount;

  /// 发布时间, 秒级时间戳.
  final int createTime;

  final String description;
  final String keywords;
  final String userName;
  final int userId;

  /// 分P数量.
  final int partCount;

  /// 站内相对地址, 部分接口不返回.
  final String? url;

  /// 分P列表, 列表接口也会返回.
  final List<VideoPart> parts;

  factory VideoModel.fromJson(Map<String, dynamic> json) {
    final rawParts = json['video'];
    return VideoModel(
      hid: json['hid']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      typeId: int.tryParse(json['typeid']?.toString() ?? '') ?? 0,
      typeName: json['typename']?.toString() ?? '',
      cover: json['thumb']?.toString() ?? '',
      playCount: int.tryParse(json['play']?.toString() ?? '') ?? 0,
      danmakuCount: int.tryParse(json['mukio']?.toString() ?? '') ?? 0,
      createTime: int.tryParse(json['create']?.toString() ?? '') ?? 0,
      description: json['description']?.toString() ?? '',
      keywords: json['keywords']?.toString() ?? '',
      userName: json['user']?.toString() ?? '',
      userId: int.tryParse(json['userid']?.toString() ?? '') ?? 0,
      partCount: int.tryParse(json['part']?.toString() ?? '') ?? 1,
      url: json['url']?.toString(),
      parts: rawParts is List
          ? rawParts
                .whereType<Map>()
                .map((e) => VideoPart.fromJson(e.cast<String, dynamic>()))
                .toList()
          : const [],
    );
  }
}
