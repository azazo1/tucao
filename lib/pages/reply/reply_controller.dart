import 'package:get/get.dart';
import 'package:tucao/common/controller/paging_controller.dart';
import 'package:tucao/http/api_path.dart';
import 'package:tucao/http/reply_http.dart';
import 'package:tucao/models/reply.dart';
import 'package:tucao/pages/reply/reply_thread.dart';
import 'package:tucao/services/account_service.dart';
import 'package:tucao/utils/logger.dart';

/// 去掉异常前缀, 让提示可读.
String? cleanReplyError(String? raw) {
  if (raw == null) {
    return null;
  }
  var text = raw.trim();
  if (text.isEmpty) {
    return null;
  }
  for (final prefix in ['Exception: ', 'DioException ', 'FormatException: ']) {
    if (text.startsWith(prefix)) {
      text = text.substring(prefix.length);
    }
  }
  if (text.startsWith('[')) {
    final end = text.indexOf(']');
    if (end > 0) {
      text = text.substring(end + 1).trim();
    }
  }
  return text.isEmpty ? null : text;
}

/// 评论页控制器.
///
/// 一级评论分页拉取, 楼中楼只在展开时拉取.
/// 楼中楼不写回一级评论对象: 列表项只在列表真正变化时重建,
/// 把回复塞进旧对象会导致展开后拿不到新内容.
class ReplyController extends PagingController<ReplyModel> {
  ReplyController({required this.typeId, required this.hid, this.part = 0});

  /// 视频所在分区, 评论接口的 id 由它与 hid 组成.
  final int typeId;

  final String hid;

  /// 分 P 序号, 从 0 开始.
  final int part;

  /// 楼中楼每页条数.
  int get replyPageSize => 20;

  /// 各一级评论下的楼中楼状态, 键是一级评论 id.
  final threads = <String, ReplyThread>{}.obs;

  /// 已展开楼中楼的评论 id.
  final expanded = <String>{}.obs;

  /// 本次会话内点赞过的评论 id.
  final supported = <String>{}.obs;

  /// 发送回复后本地累加的楼中楼数量, 键是一级评论 id.
  ///
  /// 站点的一级评论计数要重新拉列表才会更新, 这里先本地补上,
  /// 避免发完回复后按钮还显示旧数字.
  final _localReplyCounts = <String, int>{}.obs;

  /// 正在发送评论.
  final sending = false.obs;

  @override
  Future<List<ReplyModel>> fetchPage(int page) async {
    final result = await ReplyHttp.list(
      typeId: typeId,
      hid: hid,
      page: page,
      pageSize: pageSize,
    );
    total.value = result.total;
    return result.list;
  }

  /// 拉取楼中楼, 子类可覆盖以便测试.
  Future<ReplyPage> fetchReplies(int replyId, int page) {
    return ReplyHttp.list(
      typeId: typeId,
      hid: hid,
      page: page,
      pageSize: replyPageSize,
      replyId: replyId,
    );
  }

  @override
  Future<void> loadFirst() async {
    _resetThreads();
    await super.loadFirst();
  }

  @override
  Future<void> refresh() async {
    _resetThreads();
    await super.refresh();
  }

  void _resetThreads() {
    threads.clear();
    expanded.clear();
    _localReplyCounts.clear();
  }

  /// 某条一级评论的楼中楼状态.
  ReplyThread threadOf(String id) => threads[id] ?? const ReplyThread();

  /// 点赞数, 本次会话内点过赞的评论本地加一.
  int supportCount(ReplyModel comment) =>
      comment.support + (supported.contains(comment.id) ? 1 : 0);

  bool isSupported(String id) => supported.contains(id);

  /// 展示用的回复总数.
  ///
  /// 站点的 replys 可能滞后, 与已加载条数和本地累加值取最大.
  int replyCount(ReplyModel comment) {
    var count = comment.replyCount;
    final loaded = threadOf(comment.id).items.length;
    if (loaded > count) {
      count = loaded;
    }
    final local = _localReplyCounts[comment.id];
    if (local != null && local > count) {
      count = local;
    }
    return count;
  }

  /// 是否还能继续加载后续页.
  bool hasMoreReplies(ReplyModel comment) {
    final thread = threadOf(comment.id);
    return !thread.exhausted && thread.items.length < replyCount(comment);
  }

  /// 展开或收起某条评论的楼中楼.
  Future<void> toggleReplies(ReplyModel comment) async {
    if (expanded.contains(comment.id)) {
      collapseReplies(comment);
      return;
    }
    if (threadOf(comment.id).items.isNotEmpty) {
      expanded.add(comment.id);
      return;
    }
    await loadReplies(comment);
  }

  /// 收起楼中楼, 保留已加载的数据.
  void collapseReplies(ReplyModel comment) {
    expanded.remove(comment.id);
  }

  /// 拉取楼中楼第一页并展开.
  Future<void> loadReplies(ReplyModel comment, {bool force = false}) async {
    final id = comment.id;
    final replyId = int.tryParse(id);
    if (replyId == null) {
      return;
    }
    final thread = threadOf(id);
    if (thread.loading || thread.loadingMore) {
      return;
    }
    if (!force && thread.items.isNotEmpty) {
      expanded.add(id);
      return;
    }
    threads[id] = thread.copyWith(loading: true, error: null, failedPage: 0);
    try {
      final result = await fetchReplies(replyId, 1);
      threads[id] = threadOf(id).copyWith(
        items: result.list,
        loading: false,
        page: 1,
        failedPage: 0,
        exhausted: result.list.length < replyPageSize,
        error: null,
      );
      expanded.add(id);
    } catch (e, stackTrace) {
      Log.e('加载楼中楼失败 id=$id', error: e, stackTrace: stackTrace);
      threads[id] = threadOf(id)
          .copyWith(loading: false, failedPage: 1, error: e.toString());
      rethrow;
    }
  }

  /// 加载楼中楼后续页.
  Future<void> loadMoreReplies(ReplyModel comment) async {
    final id = comment.id;
    final replyId = int.tryParse(id);
    if (replyId == null) {
      return;
    }
    final thread = threadOf(id);
    if (thread.loading || thread.loadingMore || thread.exhausted) {
      return;
    }
    threads[id] = thread.copyWith(
      loadingMore: true,
      error: null,
      failedPage: 0,
    );
    final nextPage = thread.page + 1;
    try {
      final result = await fetchReplies(replyId, nextPage);
      final merged = <ReplyModel>[...thread.items];
      final known = merged.map((item) => item.id).toSet();
      for (final item in result.list) {
        if (known.add(item.id)) {
          merged.add(item);
        }
      }
      threads[id] = threadOf(id).copyWith(
        items: merged,
        loadingMore: false,
        page: nextPage,
        failedPage: 0,
        exhausted: result.list.length < replyPageSize,
        error: null,
      );
    } catch (e, stackTrace) {
      Log.e(
        '加载更多楼中楼失败 id=$id page=$nextPage',
        error: e,
        stackTrace: stackTrace,
      );
      threads[id] = threadOf(
        id,
      ).copyWith(loadingMore: false, failedPage: nextPage, error: e.toString());
      rethrow;
    }
  }

  /// 失败后重试: 第一页失败就重拉第一页, 后续页失败就重拉后续页.
  Future<void> retryReplies(ReplyModel comment) {
    final thread = threadOf(comment.id);
    if (thread.failedPage <= 1) {
      return loadReplies(comment, force: true);
    }
    return loadMoreReplies(comment);
  }

  /// 发送评论, 成功后刷新对应列表.
  ///
  /// [replyTo] 不为空时表示回复该条评论, 发送后重新拉取它所在楼的第一页并展开.
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
      // 内容已经发出, 后续刷新失败不能当成发送失败.
      try {
        if (replyTo == null) {
          await refresh();
          return;
        }
        final root = _rootOf(replyTo);
        if (root == null) {
          await refresh();
          return;
        }
        _localReplyCounts[root.id] = replyCount(root) + 1;
        await loadReplies(root, force: true);
      } catch (e, stackTrace) {
        Log.e('评论已发送, 但刷新评论列表失败', error: e, stackTrace: stackTrace);
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

  /// 回复任意楼层时找到它所属的一级评论.
  ReplyModel? _rootOf(ReplyModel reply) {
    if (reply.isRoot) {
      return _findRoot(reply.id) ?? reply;
    }
    final root = _findRoot(reply.replyId.toString());
    if (root != null) {
      return root;
    }
    // 个别旧数据没有 replyid, 退回到已加载的楼中楼里反查.
    for (final item in list) {
      if (threadOf(item.id).items.any((child) => child.id == reply.id)) {
        return item;
      }
    }
    return null;
  }

  ReplyModel? _findRoot(String id) {
    for (final item in list) {
      if (item.id == id) {
        return item;
      }
    }
    return null;
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
  final match = RegExp(r'"(?:msg|message|info)"\s*:\s*"([^"]*)"')
      .firstMatch(text);
  final message = match?.group(1)?.trim();
  return message == null || message.isEmpty ? null : message;
}
