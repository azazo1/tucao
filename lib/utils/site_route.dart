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
///
/// 站点域名时常更换, 用户手里的链接可能来自新域名或镜像域名, 所以域名
/// 对不上时只看路径: 能解析成站内页面 (见 [siteRouteOf]) 的 http(s) 地址
/// 也算. 这里的输入是用户自己粘贴的, 富文本里别人提交的链接不走这条规则.
Uri? parseSiteUrlInput(String raw) {
  final text = raw.trim();
  if (text.isEmpty) {
    return null;
  }
  final parsed = Uri.tryParse(text);
  final uri = parsed != null && parsed.hasScheme
      ? parsed
      : Uri.tryParse('https://$text');
  if (uri == null) {
    return null;
  }
  if (isSiteUrl(uri.toString())) {
    return uri;
  }
  final scheme = uri.scheme.toLowerCase();
  final isWeb = scheme == 'http' || scheme == 'https';
  if (isWeb && uri.host.isNotEmpty && siteRouteOf(uri) != null) {
    return uri;
  }
  return null;
}

/// 搜索栏里直接输入的站内编号, 例如 `h4070523`, `H4070523#2`,
/// `h4070523/`, `play/h4070523/`, `/play/d7120/`, `u82749`.
final _bareId = RegExp(
  r'^(/?play/)?([hdu])([0-9]+)/?(?:#([0-9]+))?$',
  caseSensitive: false,
);

/// 不带 `play/` 的编号至少要有这么多位.
///
/// `h264`, `h265` 是常见的编码名, `u2` 之类也可能是正经关键词,
/// 位数太少时仍按关键词搜索. 真实的视频编号是 7 位, 档案和用户编号也有 4 位以上.
const _minBareIdDigits = 4;

/// 纯数字按视频编号处理的最少位数.
///
/// 视频编号都是 7 位, `2024`, `1080` 这类较短的数字更可能是关键词.
final _bareHid = RegExp(r'^[0-9]{7,}$');

/// 分享文案里夹带的链接, 遇到空白, 引号或中文标点时截止.
final _urlInText = RegExp(r'''https?://[^\s<>"'，。、；！？）】」』]+''');

/// 把用户输入当作站内编号解析, 不像编号的输入返回 null.
///
/// 输入法全角状态下打出来的 `ｈ４０７０５２３` 先转成半角再判断.
/// 视频编号可以用站点的 `#分P` 写法带上分P, 分P从 1 开始.
SiteRoute? parseSiteIdInput(String raw) {
  final text = _toHalfWidth(raw).trim();
  final match = _bareId.firstMatch(text);
  if (match != null) {
    final id = match.group(3)!;
    final hasPlayPrefix = match.group(1) != null;
    if (!_nonZero.hasMatch(id) ||
        (!hasPlayPrefix && id.length < _minBareIdDigits)) {
      return null;
    }
    return switch (match.group(2)!.toLowerCase()) {
      'h' => SiteRoute(
        kind: SiteRouteKind.video,
        id: id,
        part: _partOf(match.group(4) ?? ''),
      ),
      'd' => SiteRoute(kind: SiteRouteKind.article, id: id),
      _ => SiteRoute(kind: SiteRouteKind.space, id: id),
    };
  }
  if (_bareHid.hasMatch(text) && _nonZero.hasMatch(text)) {
    return SiteRoute(kind: SiteRouteKind.video, id: text);
  }
  return null;
}

/// 从分享文案里找出第一个能打开站内页面的链接, 找不到返回 null.
///
/// 浏览器和聊天软件分享出来的常是 "标题 + 链接" 的一段文字, 整段不是地址,
/// 这里逐个取出其中的链接判断, 只认能解析成站内页面的那个.
SiteRoute? findSiteRouteInText(String raw) {
  // 链接本身都是半角, 不做全角转换, 免得把紧跟链接的中文逗号变成半角并进链接里.
  for (final match in _urlInText.allMatches(raw)) {
    // 句末的半角标点不属于链接.
    final url = match.group(0)!.replaceFirst(RegExp(r'[.,;:!?)\]}]+$'), '');
    final uri = parseSiteUrlInput(url);
    final route = uri == null ? null : siteRouteOf(uri);
    if (route != null) {
      return route;
    }
  }
  return null;
}

/// 全角 ASCII 字符 (U+FF01 到 U+FF5E) 转成对应的半角字符, 其余字符保持不变.
String _toHalfWidth(String text) {
  return String.fromCharCodes(
    text.runes.map(
      (rune) => rune >= 0xFF01 && rune <= 0xFF5E ? rune - 0xFEE0 : rune,
    ),
  );
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
