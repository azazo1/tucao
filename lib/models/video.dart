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
      file: _repairFile(json),
      vid: json['vid']?.toString(),
      type: json['type']?.toString(),
      title: json['title']?.toString() ?? '',
    );
  }

  /// 分P对象里已知的字段, 其余的键视为被截断的地址片段.
  static const _knownKeys = {'type', 'file', 'vid', 'title'};

  /// 取出直链, 必要时把被截断的地址拼回来.
  ///
  /// TOFIX(site): `api_v2/view.php` 像解析 query string 一样把
  /// `type=video&file=...` 按 `&` 拆开, 文件路径里自带的 `&` 也被当成分隔符.
  /// 结果 `file` 只剩第一个 `&` 之前的部分, 后面每一段变成值为 null 的多余键,
  /// 例如 h4079710 的 `【澄空學園&動漫國字幕組】` 与 `[DMG&SumiSora]`.
  /// 截断地址返回的是一段 JSON 错误, 播放器报 "Failed to recognize file format".
  ///
  /// 站点侧应只在第一个 `=` 处切分 `file=` 之后的整段, 或在入库时把 `&`
  /// 编码成 `%26`. 修好之前, 这里按原顺序用 `&` 把值为 null 的多余键接回
  /// `file` 后面, 依赖 [Map] 保留 JSON 的键顺序. 站点修好之后不会再有这类键,
  /// 这段逻辑自然不生效, 届时可以删掉. 片段里如果还带 `=`, 会被拆成有值的键,
  /// 这种情况无法可靠还原, 这里不处理.
  static String? _repairFile(Map<String, dynamic> json) {
    final file = json['file']?.toString();
    if (file == null || file.isEmpty) {
      return file;
    }
    final fragments = [
      for (final entry in json.entries)
        if (entry.value == null && !_knownKeys.contains(entry.key)) entry.key,
    ];
    if (fragments.isEmpty) {
      return file;
    }
    return [file, ...fragments].join('&');
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
