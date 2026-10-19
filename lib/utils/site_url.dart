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
