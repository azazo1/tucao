import 'package:get/get.dart';
import 'package:tucao/common/controller/paging_controller.dart';
import 'package:tucao/http/api_path.dart';
import 'package:tucao/http/reply_http.dart';
import 'package:tucao/models/reply.dart';
import 'package:tucao/services/account_service.dart';
import 'package:tucao/utils/logger.dart';

/// 清洗评论内容.
///
/// 站点返回的正文里混有 html 标签与转义实体, 这里做最基本的还原,
/// 不做完整的 html 解析.
String cleanReplyContent(String raw) {
  final text = raw
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]+>'), '');
  var result = text;
  for (final entry in _entities.entries) {
    result = result.replaceAll(entry.key, entry.value);
  }
  return result.trim();
}

/// `&amp;` 放在最后替换, 避免二次解码.
const _entities = <String, String>{
  '&lt;': '<',
  '&gt;': '>',
  '&quot;': '"',
  '&#39;': "'",
  '&nbsp;': ' ',
  '&amp;': '&',
};

/// 评论页控制器.
///
/// 一级评论分页拉取, 楼中楼只在展开时拉取, 拉取后缓存在评论对象上.
class ReplyController extends PagingController<ReplyModel> {
  ReplyController({
    required this.typeId,
    required this.hid,
    this.part = 0,
  });

  /// 视频 id, 不带 h 前缀.
  /// 视频所在分区, 评论接口的 id 由它与 hid 组成.
  final int typeId;

  final String hid;

  /// 分 P 序号, 从 0 开始.
  final int part;

  /// 已展开楼中楼的评论 id.
  final expanded = <String>{}.obs;

  /// 正在拉取楼中楼的评论 id.
  final loadingReplies = <String>{}.obs;

  /// 本次会话内点赞过的评论 id.
  final supported = <String>{}.obs;

  /// 正在发送评论.
  final sending = false.obs;

  @override
  Future<List<ReplyModel>> fetchPage(int page) async {
    final result = await ReplyHttp.list(
      typeId: typeId,
      hid: hid,
      page: page,
      pageSize: pageSize,
      hot: true,
    );
    total.value = result.total;
    return result.list;
  }

  @override
  Future<void> loadFirst() async {
    expanded.clear();
    await super.loadFirst();
  }

  @override
  Future<void> refresh() async {
    expanded.clear();
    await super.refresh();
  }

  /// 点赞数, 本次会话内点过赞的评论本地加一.
  int supportCount(ReplyModel comment) =>
      comment.support + (supported.contains(comment.id) ? 1 : 0);

  bool isSupported(String id) => supported.contains(id);

  /// 展开或收起某条评论的楼中楼.
  Future<void> toggleReplies(ReplyModel comment) async {
    if (expanded.contains(comment.id)) {
      expanded.remove(comment.id);
      return;
    }
    if (comment.replies.isNotEmpty) {
      expanded.add(comment.id);
      return;
    }
    await loadReplies(comment);
  }

  /// 拉取楼中楼回复, 结果缓存在评论对象上.
  Future<void> loadReplies(ReplyModel comment, {bool force = false}) async {
    final id = comment.id;
    final replyId = int.tryParse(id);
    if (replyId == null || loadingReplies.contains(id)) {
      return;
    }
    if (!force && comment.replies.isNotEmpty) {
      expanded.add(id);
      return;
    }
    loadingReplies.add(id);
    try {
      final result = await ReplyHttp.list(
        typeId: typeId,
        hid: hid,
        page: 1,
        pageSize: pageSize,
        replyId: replyId,
        hot: true,
      );
      _cacheReplies(id, result.list);
      expanded.add(id);
    } catch (e, stackTrace) {
      Log.e('加载楼中楼失败 id=$id', error: e, stackTrace: stackTrace);
      rethrow;
    } finally {
      loadingReplies.remove(id);
    }
  }

  /// 发送评论, 成功后刷新对应列表.
  ///
  /// [replyTo] 不为空时表示回复该条评论, 发送后刷新它的楼中楼.
  Future<void> send(String content, {ReplyModel? replyTo}) async {
    _requireLogin();
    final text = content.trim();
    if (text.isEmpty) {
      throw Exception('评论内容不能为空');
    }
    sending.value = true;
    try {
      final raw = await ReplyHttp.send(
        typeId: typeId,
        hid: hid,
        content: text,
        replyId: replyTo == null ? null : int.tryParse(replyTo.id),
        // 回复时要告诉站点回复给谁, 缺失会被拒收.
        replyUid: replyTo?.userId,
      );
      _checkResult(raw, '评论发送失败');
      if (replyTo == null) {
        await refresh();
      } else {
        await loadReplies(replyTo, force: true);
      }
    } finally {
      sending.value = false;
    }
  }

  /// 点赞评论, 成功后本地加一并记录.
  Future<void> support(ReplyModel comment) async {
    _requireLogin();
    if (supported.contains(comment.id)) {
      return;
    }
    final commentId = comment.commentId.isNotEmpty
        ? comment.commentId
        : ApiPath.commentId(typeId, hid);
    final raw = await ReplyHttp.support(commentId: commentId, id: comment.id);
    _checkResult(raw, '点赞失败');
    supported.add(comment.id);
  }

  void _cacheReplies(String id, List<ReplyModel> replies) {
    final index = list.indexWhere((item) => item.id == id);
    if (index < 0) {
      return;
    }
    list[index] = list[index].copyWith(replies: replies);
  }

  void _requireLogin() {
    if (!AccountService.instance.isLogin) {
      throw Exception('请先登录');
    }
  }

  /// 接口以 json 返回失败时抛出可读提示, 返回 html 等情况按成功处理.
  void _checkResult(String raw, String fallback) {
    final text = raw.trim();
    if (text.isEmpty) {
      return;
    }
    final code = _codeOf(text);
    if (code != null && code < 0) {
      throw Exception(_messageOf(text) ?? fallback);
    }
    if (text.contains('请先登录') || text.contains('您需要登录')) {
      throw Exception('请先登录');
    }
  }
}

int? _codeOf(String text) {
  final match = RegExp(r'"code"\s*:\s*(-?\d+)').firstMatch(text);
  return match == null ? null : int.tryParse(match.group(1)!);
}

String? _messageOf(String text) {
  final match = RegExp(
    r'"(?:msg|message|info)"\s*:\s*"([^"]*)"',
  ).firstMatch(text);
  final message = match?.group(1)?.trim();
  return message == null || message.isEmpty ? null : message;
}
