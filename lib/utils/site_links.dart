import 'package:tucao/common/constants.dart';

/// 只根据站内编号生成链接, 不直接打开接口返回的任意 URL.
abstract final class SiteLinks {
  /// 应用分P从 0 开始, 站点锚点从 1 开始.
  static Uri? video(String hid, {int part = 0}) {
    if (!RegExp(r'^[0-9]+$').hasMatch(hid) ||
        !hid.contains(RegExp(r'[1-9]')) ||
        part < 0) {
      return null;
    }
    return Uri.parse(
      Constants.baseUrl,
    ).resolve('play/h$hid/').replace(fragment: (part + 1).toString());
  }
}
