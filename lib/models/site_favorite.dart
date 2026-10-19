import 'package:tucao/models/video.dart';

/// 站点账号里的一条追番.
///
/// 站点没有查询单条状态的接口, 会员中心也没有 json 版本, 只能解析追番夹页面;
/// 页面上的每条记录都带取消追番需要的记录号, 因此这里一并保存.
class SiteFavoriteItem {
  const SiteFavoriteItem({
    required this.recordId,
    required this.hid,
    required this.title,
    this.cover = '',
    this.typeName = '',
    this.userName = '',
    this.savedDate = '',
    this.description = '',
  });

  /// 追番记录号, 取消追番时作为 `id` 参数.
  final int recordId;

  /// 视频编号; 站点里还有档案一类内容, 它们不属于视频, 这里为空.
  final String hid;

  final String title;
  final String cover;

  /// 分区名.
  final String typeName;

  /// 投稿人昵称.
  final String userName;

  /// 追番日期, 取站点原样的 `2026-10-19`.
  final String savedDate;

  final String description;

  /// 是否属于视频, 只有视频才能在应用里打开.
  bool get isVideo => hid.isNotEmpty;

  /// 列表卡片需要的视频信息, 播放页会自己再取一次详情.
  VideoModel? get video => isVideo
      ? VideoModel(
          hid: hid,
          title: title,
          cover: cover,
          typeName: typeName,
          userName: userName,
          description: description,
        )
      : null;

  @override
  String toString() => 'SiteFavoriteItem($recordId, $hid, $title)';
}
