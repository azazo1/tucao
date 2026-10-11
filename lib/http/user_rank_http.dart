import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:tucao/common/constants.dart';
import 'package:tucao/utils/http_util.dart';
import 'package:tucao/utils/logger.dart';

/// u榜里的一个用户条目.
class UserRankItem {
  const UserRankItem({
    required this.userId,
    required this.userName,
    required this.rank,
    this.avatar = '',
    this.badge = '',
  });

  final int userId;
  final String userName;

  /// 排名, 取自条目上的序号.
  final int rank;

  final String avatar;

  /// 用户身上的标签, 例如 1元9次.
  final String badge;
}

/// u榜的一个分组.
class UserRankGroup {
  const UserRankGroup({required this.title, required this.list});

  /// 分组名, 站点用的是 失足, 存活 这类趣味分类.
  final String title;

  final List<UserRankItem> list;
}

/// u榜数据源.
///
/// 该榜单列的是用户而不是视频, 链接形如 `/play/u{uid}/`,
/// 因此不能复用视频榜单的解析, 需要单独处理.
abstract final class UserRankHttp {
  static Future<List<UserRankGroup>> fetch({CancelToken? cancelToken}) async {
    final response = await HttpUtil.dio.get(
      '${Constants.baseUrl}html/user_hot.html',
      options: Options(headers: {'user-agent': Constants.desktopUserAgent}),
      cancelToken: cancelToken,
    );
    return parseUserRankHtml(response.data.toString());
  }

  /// 解析 u榜页面.
  ///
  /// 结构与其它榜单相似, 分组容器是 `div.time_item`,
  /// 但条目里是用户头像与昵称, 地址为 `/play/u{uid}/`.
  static List<UserRankGroup> parseUserRankHtml(String raw) {
    final document = html_parser.parse(raw);
    final groups = <UserRankGroup>[];

    for (final section in document.querySelectorAll('.time_item')) {
      final title = section.querySelector('.time_title')?.text.trim() ?? '';
      final list = <UserRankItem>[];
      final seen = <int>{};
      for (final item in section.querySelectorAll('.item')) {
        final link = item.querySelector('a.t') ?? item.querySelector('a');
        if (link == null) {
          continue;
        }
        final userId = _parseUserId(link.attributes['href'] ?? '');
        if (userId == null || !seen.add(userId)) {
          continue;
        }
        final image = item.querySelector('img');
        list.add(
          UserRankItem(
            userId: userId,
            userName: item.querySelector('.u')?.text.trim() ?? link.text.trim(),
            rank: _rankOf(item, list.length + 1),
            avatar: _avatar(image),
            badge: item.querySelector('.c')?.text.trim() ?? '',
          ),
        );
      }
      if (list.isEmpty) {
        continue;
      }
      groups.add(UserRankGroup(title: title, list: list));
    }

    Log.i('u榜解析完成, 共 ${groups.length} 组');
    return groups;
  }

  static int? _parseUserId(String href) {
    final match = RegExp(r'/play/u(\d+)/').firstMatch(href);
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  /// 条目上的排名.
  ///
  /// 站点只给前三名加 `n123` 类名, 其余条目的序号在无类名的 p 元素里,
  /// 因此这里直接找条目里的第一个 p, 取不到时按顺序号兜底.
  static int _rankOf(dynamic item, int fallback) {
    final node = item.querySelector('p');
    final parsed = int.tryParse(node?.text.trim() ?? '');
    return parsed ?? fallback;
  }

  /// 头像地址, 站点用的是相对路径, 这里补成绝对地址.
  static String _avatar(dynamic image) {
    final src = image?.attributes['src'] as String? ?? '';
    if (src.isEmpty || src.startsWith('http')) {
      return src;
    }
    return '${Constants.baseUrl}${src.replaceFirst(RegExp(r'^/'), '')}';
  }
}
