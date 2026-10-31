import 'package:tucao/common/constants.dart';

/// 只根据站内编号生成链接, 不直接打开接口返回的任意 URL.
abstract final class SiteLinks {
  static final _id = RegExp(r'^[0-9]+$');

  /// 编号必须是纯数字且不全为 0.
  static bool _validId(String id) =>
      _id.hasMatch(id) && id.contains(RegExp(r'[1-9]'));

  static Uri _site(String path) => Uri.parse(Constants.baseUrl).resolve(path);

  /// 应用分P从 0 开始, 站点锚点从 1 开始.
  static Uri? video(String hid, {int part = 0}) {
    if (!_validId(hid) || part < 0) {
      return null;
    }
    return _site('play/h$hid/').replace(fragment: (part + 1).toString());
  }

  /// 档案详情, 站点沿用播放页模板, 路径前缀是 `d`.
  static Uri? article(String hid) {
    if (!_validId(hid)) {
      return null;
    }
    return _site('play/d$hid/');
  }

  /// 用户空间, 即投稿人主页.
  static Uri? space(int userId) {
    if (userId <= 0) {
      return null;
    }
    return _site('play/u$userId/');
  }

  /// 档案列表, [keyword] 为空表示全部分类.
  static Uri articleList({String? keyword}) {
    final uri = _site('data/');
    if (keyword == null || keyword.isEmpty) {
      return uri;
    }
    return uri.replace(queryParameters: {'keywords': keyword});
  }
}
