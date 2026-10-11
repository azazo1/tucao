import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:tucao/common/constants.dart';
import 'package:tucao/http/api_path.dart';
import 'package:tucao/models/video.dart';
import 'package:tucao/utils/http_util.dart';
import 'package:tucao/utils/logger.dart';

/// 用户空间信息.
class SpaceInfo {
  const SpaceInfo({
    required this.userId,
    required this.userName,
    this.avatar = '',
    this.banner = '',
    this.sign = '',
    this.meta = '',
    this.total = 0,
  });

  final int userId;
  final String userName;

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
  /// 站点用户空间每页固定返回的条数.
  static const pageSize = 50;

  static Future<SpacePage> fetch({
    required int userId,
    int page = 1,
    CancelToken? cancelToken,
  }) async {
    final response = await HttpUtil.dio.get(
      '${Constants.baseUrl}${ApiPath.userUrl(userId)}',
      queryParameters: {if (page > 1) 'page': page},
      options: Options(headers: {'user-agent': Constants.desktopUserAgent}),
      cancelToken: cancelToken,
    );
    return parseSpaceHtml(response.data.toString(), userId, page);
  }

  /// 解析用户空间页面.
  ///
  /// 头部是 `div.sheader`: `img.avatar` 头像, `img.banner` 背景,
  /// `h1` 昵称, 两个 `p` 分别是标签与签名; 下面是 `div.list` 里的投稿列表.
  static SpacePage parseSpaceHtml(String raw, int userId, int page) {
    final document = html_parser.parse(raw);
    final header = document.querySelector('.sheader');

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

    Log.i('用户空间解析完成, uid=$userId 第 $page 页, ${list.length} 条');
    return SpacePage(
      info: SpaceInfo(
        userId: userId,
        userName: header?.querySelector('h1')?.text.trim() ?? '',
        avatar: _absolute(avatar),
        banner: _absolute(banner),
        sign: sign,
        meta: meta,
        total: total,
      ),
      list: list,
      hasMore: hasMore,
    );
  }

  static String? _parseHid(String href) {
    final match = RegExp(r'/play/h?(\d+)/').firstMatch(href);
    return match?.group(1);
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
