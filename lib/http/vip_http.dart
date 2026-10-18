import 'package:dio/dio.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:tucao/common/constants.dart';
import 'package:tucao/common/vip.dart';
import 'package:tucao/http/api_path.dart';
import 'package:tucao/utils/http_util.dart';
import 'package:tucao/utils/logger.dart';

/// 破会员标记的数据源.
///
/// 评论 json 接口不带会员信息, 站点只在服务端渲染的评论页里给破会员的昵称
/// 上色, 因此这里按页抓评论页 HTML, 解析出该页的破会员 uid.
///
/// 站点接口以后若有变化, 处理方式如下:
/// - 若评论 json 接口给每条评论补上会员字段 (vip / groupid / 昵称颜色),
///   应当删掉这里的页面解析, 改为直接读 json 字段, 评论列表就少一次请求.
/// - 若站点换了会员昵称颜色, 或者改用图标 / 头衔文字标记, 只需调整
///   [Vip] 与 [parseCommentVipUids] 的判断, 调用方不用动.
/// - 若评论页以后要求登录才能访问, 抓取会失败, 评论列表照常显示, 只是没有
///   会员标记.
abstract final class VipHttp {
  /// 抓取某一页评论页, 返回该页里破会员的 uid.
  ///
  /// 评论页与评论 json 接口都从第 1 页开始编号, 页码对齐时覆盖的是同一批
  /// 一级评论; 楼中楼两级都不带会员信息, 站点自己也没有.
  static Future<List<int>> fetchCommentVipUids({
    required int typeId,
    required String hid,
    int page = 1,
    CancelToken? cancelToken,
  }) async {
    final response = await HttpUtil.dio.get(
      '${Constants.baseUrl}${ApiPath.replyInit}',
      queryParameters: {
        'commentid': ApiPath.commentId(typeId, hid),
        'iframe': 1,
        'page': page,
      },
      cancelToken: cancelToken,
    );
    return parseCommentVipUids(response.data.toString());
  }

  /// 解析评论页里的破会员 uid.
  ///
  /// 每条一级评论是 `div.clist div.item`: 头像与昵称外面套着 `/play/u{uid}/`
  /// 链接, 会员颜色写在昵称元素的 style 上; 站内推广条没有 uid 链接, 会被跳过.
  static List<int> parseCommentVipUids(String raw) {
    if (raw.trim().isEmpty) {
      return const [];
    }
    final document = html_parser.parse(raw);
    final uids = <int>{};
    for (final item in document.querySelectorAll('.clist .item')) {
      final uid = _parseUid(
        item.querySelector('a[href*="/play/u"]')?.attributes['href'],
      );
      if (uid == null) {
        continue;
      }
      if (Vip.hasNicknameColor(_nicknameStyle(item))) {
        uids.add(uid);
      }
    }
    Log.d('评论页解析完成, 破会员 ${uids.length} 人');
    return uids.toList();
  }

  /// 昵称元素的 style, 会员颜色写在昵称链接或纯文本昵称的 span 上.
  static String _nicknameStyle(Element item) {
    final name = item.querySelector('.cu');
    if (name == null) {
      return '';
    }
    for (final node in [name.querySelector('a'), name.querySelector('span')]) {
      final style = node?.attributes['style'] ?? '';
      if (Vip.hasNicknameColor(style)) {
        return style;
      }
    }
    return name.attributes['style'] ?? '';
  }

  static int? _parseUid(String? href) {
    if (href == null || href.isEmpty) {
      return null;
    }
    return int.tryParse(
      RegExp(r'/play/u(\d+)/').firstMatch(href)?.group(1) ?? '',
    );
  }
}
