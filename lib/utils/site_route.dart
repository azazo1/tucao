import 'package:tucao/utils/site_url.dart';

/// 站内地址对应的应用内页面种类.
enum SiteRouteKind {
  /// 视频播放页, 路径前缀 `h`.
  video,

  /// 档案详情, 路径前缀 `d`.
  article,

  /// 投稿人主页, 路径前缀 `u`.
  space,
}

/// 从站内地址解析出的应用内页面.
class SiteRoute {
  const SiteRoute({required this.kind, required this.id, this.part});

  final SiteRouteKind kind;

  /// 站点内容编号, 视频与档案是 hid, 投稿人主页是 uid.
  final String id;

  /// 视频分P, 从 0 开始; 为空时由播放页按观看历史恢复.
  final int? part;
}

/// 站点沿用播放页模板区分内容: `play/h{hid}/` 视频, `play/d{hid}/` 档案,
/// `play/u{uid}/` 投稿人主页.
final _path = RegExp(r'^/play/([hdu])([0-9]+)/?$');

/// 编号必须是纯数字且不全为 0, 站点的空内容页都是 0.
final _id = RegExp(r'^[0-9]+$');
final _nonZero = RegExp(r'[1-9]');

/// 分P锚点由站点从 1 开始编号.
final _anchor = RegExp(r'^[0-9]+$');

/// 把用户输入当作站点地址解析, 站外地址与不像地址的写法都返回 null.
///
/// 搜索栏允许直接粘贴站点链接, 用户从浏览器地址栏复制的写法常常省略协议,
/// 这里先补上 https 再判断. 省略协议时主机名就是输入的第一段, 因此普通
/// 关键词不会被误认成地址.
Uri? parseSiteUrlInput(String raw) {
  final text = raw.trim();
  if (text.isEmpty) {
    return null;
  }
  final parsed = Uri.tryParse(text);
  final uri = parsed != null && parsed.hasScheme
      ? parsed
      : Uri.tryParse('https://$text');
  if (uri == null || !isSiteUrl(uri.toString())) {
    return null;
  }
  return uri;
}

/// 站内地址对应的应用内页面, 站点没有对应页面时返回 null.
SiteRoute? siteRouteOf(Uri uri) {
  final match = _path.firstMatch(uri.path);
  if (match == null) {
    return null;
  }
  final id = match.group(2)!;
  if (!_id.hasMatch(id) || !_nonZero.hasMatch(id)) {
    return null;
  }
  switch (match.group(1)) {
    case 'h':
      return SiteRoute(
        kind: SiteRouteKind.video,
        id: id,
        part: _partOf(uri.fragment),
      );
    case 'd':
      return SiteRoute(kind: SiteRouteKind.article, id: id);
    default:
      return SiteRoute(kind: SiteRouteKind.space, id: id);
  }
}

/// 锚点是第几个分P, 应用里从 0 开始; 不是合法锚点时返回 null,
/// 交给播放页按观看历史恢复.
int? _partOf(String fragment) {
  if (!_anchor.hasMatch(fragment)) {
    return null;
  }
  final anchor = int.tryParse(fragment);
  if (anchor == null || anchor < 1) {
    return null;
  }
  return anchor - 1;
}
