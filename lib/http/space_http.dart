import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:tucao/common/constants.dart';
import 'package:tucao/common/vip.dart';
import 'package:tucao/http/api_path.dart';
import 'package:tucao/models/video.dart';
import 'package:tucao/utils/http_util.dart';
import 'package:tucao/utils/logger.dart';
import 'package:tucao/utils/site_url.dart';

/// 用户空间信息.
class SpaceInfo {
  const SpaceInfo({
    required this.userId,
    required this.userName,
    this.loginName = '',
    this.avatar = '',
    this.banner = '',
    this.sign = '',
    this.meta = '',
    this.total = 0,
    this.isVip = false,
    this.exists = true,
  });

  final int userId;
  final String userName;

  /// 站点是否有这个用户.
  ///
  /// 不存在或已注销的 uid 也会返回 200, 页面是一张只剩默认背景的空模板,
  /// 标签固定是 `正义, 1元-1次, 守护0天, 居住56年`, 而真实用户的次数不会是
  /// 负数, 用这段文案判定, 不看会被站点清空的昵称.
  /// uid 0 是游客弹幕的聚合账号, 不能当作不存在的用户.
  final bool exists;

  /// 空间主人在站点的登录用户名, 私信接口按它查收件人.
  ///
  /// 昵称 [userName] 与用户名不一定相同, 站点的私信链接里带的是后者.
  final String loginName;

  /// 头像地址.
  final String avatar;

  /// 顶部背景图.
  final String banner;

  /// 个性签名.
  final String sign;

  /// 站点给出的用户标签, 例如 正义, 守护346天.
  final String meta;

  /// 投稿总数.
  final int total;

  /// 空间主人是否是站点破会员.
  ///
  /// 站点给破会员的昵称写了 `#c07c32` 的颜色, 普通用户没有这段 style,
  /// 判定规则见 [Vip.hasNicknameColor].
  final bool isVip;
}

/// 用户空间的一页数据.
class SpacePage {
  const SpacePage({
    required this.info,
    required this.list,
    required this.hasMore,
  });

  final SpaceInfo info;
  final List<VideoModel> list;

  /// 是否还有下一页, 由页面上的分页链接判断.
  final bool hasMore;
}

/// 用户空间数据源.
///
/// 站点 `play/u{uid}/` 是投稿人的主页, 没有 json 接口, 只能抓页面,
/// 分页参数是 `?page=N`.
abstract final class SpaceHttp {
  /// 游客弹幕聚合账号的显示名.
  ///
  /// 站点把未登录用户发的弹幕都统计在 uid 0 名下, u 榜里给它的名字是
  /// 网友, 但空间页的 `h1` 是空的, 这里沿用榜单的叫法.
  static const guestUserName = '网友';

  /// 空模板上的用户标签.
  ///
  /// 不存在或已注销的 uid 也会返回 200 的页面, 标签固定是
  /// `正义, 1元-1次, 守护0天, 居住56年`; 真实用户的次数不会是负数,
  /// 这段文案只会出现在空模板上, 比昵称可靠得多.
  static const placeholderMeta = '1元-1次';

  /// 站点用户空间每页固定返回的条数.
  static const pageSize = 50;

  static Future<SpacePage> fetch({
    required int userId,
    int page = 1,
    CancelToken? cancelToken,
  }) async {
    // uid 0 只是游客弹幕的聚合账号, 不该去请求站点页面:
    // 站点对已登录的会话请求 /play/u0/ 会返回登录者自己的空间,
    // 直接构造一张空页, 页面上只显示游客聚合的说明.
    if (userId == 0) {
      return const SpacePage(
        info: SpaceInfo(userId: 0, userName: guestUserName),
        list: [],
        hasMore: false,
      );
    }
    final response = await HttpUtil.dio.get(
      '${Constants.baseUrl}${ApiPath.userUrl(userId)}',
      queryParameters: {if (page > 1) 'page': page},
      options: Options(headers: {'user-agent': Constants.desktopUserAgent}),
      cancelToken: cancelToken,
    );
    return parseSpaceHtml(
      response.data.toString(),
      userId,
      page,
      avatarRevision: DateTime.now().microsecondsSinceEpoch,
    );
  }

  /// 解析用户空间页面.
  ///
  /// 头部是 `div.sheader`: `img.avatar` 头像, `img.banner` 背景,
  /// `h1` 昵称, 两个 `p` 分别是标签与签名; 下面是 `div.list` 里的投稿列表.
  /// [avatarRevision] 随资料请求更新, 而不是随界面重绘更新.
  static SpacePage parseSpaceHtml(
    String raw,
    int userId,
    int page, {
    int? avatarRevision,
  }) {
    final document = html_parser.parse(raw);
    final header = document.querySelector('.sheader');
    final nameNode = header?.querySelector('h1');
    // 私信链接形如 index.php?m=message&c=index&a=send&username=azo1,
    // 站点私信接口要的是这里的用户名, 不是 uid.
    final loginName = _parseLoginName(
      document
              .querySelector('a[href*="a=send"][href*="username="]')
              ?.attributes['href'] ??
          '',
    );

    final avatar = header?.querySelector('img.avatar')?.attributes['src'] ?? '';
    final bannerNode = header?.querySelector('img.banner');
    // 背景图写在 style 里, 缺失时退回 src. 只解析一次, 避免依赖两次解析结果一致.
    final bannerStyle = _parseBackground(
      bannerNode?.attributes['style'] ?? '',
    );
    final banner = bannerStyle.isNotEmpty
        ? bannerStyle
        : bannerNode?.attributes['src'] ?? '';
    final paragraphs = header?.querySelectorAll('p') ?? const [];
    final meta = paragraphs.isNotEmpty ? paragraphs.first.text.trim() : '';
    final sign = paragraphs.length > 1 ? paragraphs[1].text.trim() : '';

    // 分页文案形如 "共2823条 / 第1页".
    final pagerText = document.querySelector('.title a.m')?.text.trim() ?? '';
    final total =
        int.tryParse(
          RegExp(r'共(\d+)条').firstMatch(pagerText)?.group(1) ?? '',
        ) ??
        0;

    final list = <VideoModel>[];
    final seen = <String>{};
    for (final item in document.querySelectorAll('.list .item')) {
      final link = item.querySelector('a.t');
      if (link == null) {
        continue;
      }
      final hid = _parseHid(link.attributes['href'] ?? '');
      if (hid == null || !seen.add(hid)) {
        continue;
      }
      final image = item.querySelector('img');
      list.add(
        VideoModel(
          hid: hid,
          title: link.text.trim(),
          cover: _parseCover(image),
          playCount: _parseCount(
            item.querySelector('.i span')?.text ?? '',
          ),
          userName: item.querySelector('.i a')?.text.trim() ?? '',
        ),
      );
    }

    // 站点分页链接不一定出现, 因此以本页是否取满作为主要依据,
    // 页大小固定 50, 与站点的实际行为一致.
    final hasMore = list.length >= pageSize;

    final userName = nameNode?.text.trim() ?? '';
    // 空模板的标签写着 1元-1次, 真实用户的次数不会是负数, 用它判断用户是否存在.
    // 仍保留其余资料作为兜底: 只有标签是占位文案且其它字段也全空时才认定不存在,
    // 这样站点以后改了文案也不会把所有用户都判成不存在.
    final exists =
        userId == 0 ||
        !meta.contains(placeholderMeta) ||
        userName.isNotEmpty ||
        avatar.isNotEmpty ||
        loginName.isNotEmpty ||
        total > 0 ||
        list.isNotEmpty;
    Log.i('用户空间解析完成, uid=$userId 第 $page 页, ${list.length} 条');
    return SpacePage(
      info: SpaceInfo(
        userId: userId,
        // uid 0 是游客弹幕的聚合账号, 站点没有给它昵称, 这里补一个显示名.
        userName: userName.isEmpty && userId == 0 ? guestUserName : userName,
        exists: exists,
        loginName: loginName,
        avatar: avatarUrl(avatar, revision: avatarRevision?.toString()),
        banner: _absolute(banner),
        sign: sign,
        meta: meta,
        total: total,
        isVip: Vip.hasNicknameColor(nameNode?.attributes['style']),
      ),
      list: list,
      hasMore: hasMore,
    );
  }

  static String? _parseHid(String href) {
    final match = RegExp(r'/play/h?(\d+)/').firstMatch(href);
    return match?.group(1);
  }

  /// 从空间页的私信链接里取登录用户名.
  static String _parseLoginName(String href) {
    return Uri.tryParse(href)?.queryParameters['username']?.trim() ?? '';
  }

  /// 封面地址.
  ///
  /// 站点的 img 的 src 是统一的占位图, 真实封面写在 style 的
  /// background-image 里, 缺失时退回 data-img 的第一项, 都没有才用 src.
  static String _parseCover(dynamic image) {
    if (image == null) {
      return '';
    }
    final fromStyle = _parseBackground(image.attributes['style'] ?? '');
    if (fromStyle.isNotEmpty) {
      return fromStyle;
    }
    final dataImg = (image.attributes['data-img'] ?? '')
        .split(',')
        .map((e) => e.trim())
        .firstWhere((e) => e.isNotEmpty, orElse: () => '');
    if (dataImg.isNotEmpty) {
      return dataImg;
    }
    return image.attributes['src'] ?? '';
  }

  static String _parseBackground(String style) {
    final match = RegExp(r'url\(([^)]+)\)').firstMatch(style);
    return match?.group(1)?.replaceAll(RegExp(r'''^["']|["']$'''), '').trim() ??
        '';
  }

  static int _parseCount(String text) {
    final match = RegExp(r'([\d,]+)').firstMatch(text);
    if (match == null) {
      return 0;
    }
    return int.tryParse(match.group(1)!.replaceAll(',', '')) ?? 0;
  }

  static String _absolute(String url) {
    if (url.isEmpty || url.startsWith('http')) {
      return url;
    }
    return '${Constants.baseUrl}${url.replaceFirst(RegExp(r'^/'), '')}';
  }
}
