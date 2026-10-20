import 'package:tucao/common/constants.dart';

/// 站点地址的处理.
///
/// 富文本里的图片与链接都由别人提交, 页面给的多半是相对地址, 显示前要按
/// 主站域名补全, 并判断来源是不是站点自己. 评论与系统公告共用这套规则.

/// 把站点返回的相对地址补成绝对地址.
///
/// 已经是 http(s) 的原样返回, 其余按主站域名拼接, 开头的斜杠不重复.
String absoluteSiteUrl(String raw) {
  final url = raw.trim();
  if (url.isEmpty) {
    return '';
  }
  if (url.startsWith('http://') || url.startsWith('https://')) {
    return url;
  }
  return '${Constants.baseUrl}${url.replaceFirst(RegExp(r'^/'), '')}';
}

/// 头像地址上的版本参数名.
///
/// 站点换头像后路径不变, CDN 仍把旧内容缓存 30 天, 缓存键包含查询串, 因此
/// 网页端每次访问都带一个新的时间戳来绕开它, 见 [avatarUrl].
const avatarRevisionParam = '_avatar_v';

/// 给站点头像地址补上绕开缓存的版本参数.
///
/// 站点给头像设了 30 天缓存, 换过头像的账号在旧缓存过期之前, 用页面上给出
/// 的原地址只会拿到失效的内容 (实测是 8 字节的文件头), 换版本参数才会回源.
///
/// [revision] 为空时按天生成, 当天内地址稳定, 图片与本地缓存还能复用, 每天
/// 第一次显示才重新取图. 空地址与站外地址原样返回, 不给别人的图片乱加参数.
/// 原有的查询参数全部保留, 旧的版本参数被替换.
String avatarUrl(String raw, {String? revision, DateTime? now}) {
  // 协议相对的地址在 HTML 里也常见, 补全时按站点自己的协议处理.
  final text = raw.trim();
  final url = text.startsWith('//') ? 'https:$text' : absoluteSiteUrl(text);
  if (url.isEmpty) {
    return '';
  }
  final uri = Uri.tryParse(url);
  if (uri == null || !isSiteImage(url)) {
    return url;
  }
  return uri
      .replace(
        queryParameters: {
          ...uri.queryParametersAll,
          avatarRevisionParam: revision ?? dayStamp(now ?? DateTime.now()),
        },
      )
      .toString();
}

/// 按天生成的版本号, 形如 `20261021`.
String dayStamp(DateTime time) {
  final month = time.month.toString().padLeft(2, '0');
  final day = time.day.toString().padLeft(2, '0');
  return '${time.year}$month$day';
}

/// 图片地址是否属于站点自己, 子域名与去掉 www 的主域名都算.
///
/// 富文本里的图片地址由别人提交, 站外的地址不该在列表滚动时自动联网,
/// 否则一条内容就能让本机向任意主机发请求, 界面据此改为等用户点击.
bool isSiteImage(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) {
    return false;
  }
  final scheme = uri.scheme.toLowerCase();
  if (scheme != 'http' && scheme != 'https') {
    return false;
  }
  final siteHost = Uri.tryParse(Constants.baseUrl)?.host.toLowerCase() ?? '';
  if (siteHost.isEmpty) {
    return false;
  }
  // 站点主域名可能是 www 开头, 图片地址却用裸域名或图片子域名.
  final bareHost = siteHost.startsWith('www.')
      ? siteHost.substring('www.'.length)
      : siteHost;
  final host = uri.host.toLowerCase();
  return _sameOrSubDomainOf(host, siteHost) ||
      _sameOrSubDomainOf(host, bareHost);
}

bool _sameOrSubDomainOf(String host, String domain) =>
    host == domain || host.endsWith('.$domain');
