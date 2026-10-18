import 'package:tucao/models/reply.dart';

/// 一条一级评论下的楼中楼状态.
///
/// 楼中楼按需加载, 因此这里除了已加载的回复, 还保存分页位置和加载状态.
/// 该对象只放在控制器里, 不写回 [ReplyModel], 否则列表项拿不到新数据.
class ReplyThread {
  const ReplyThread({
    this.items = const [],
    this.loading = false,
    this.loadingMore = false,
    this.error,
    this.page = 0,
    this.failedPage = 0,
    this.exhausted = false,
  });

  /// 已加载的回复, 按站点返回顺序排列.
  final List<ReplyModel> items;

  /// 正在加载第一页.
  final bool loading;

  /// 正在加载后续页.
  final bool loadingMore;

  /// 最近一次加载失败的提示.
  final String? error;

  /// 已加载到第几页, 0 表示尚未加载.
  final int page;

  /// 最近一次加载失败的页码, 0 表示没有失败.
  final int failedPage;

  /// 站点已经返回不足一页, 不再请求后续页.
  final bool exhausted;

  bool get isLoaded => page > 0;

  ReplyThread copyWith({
    List<ReplyModel>? items,
    bool? loading,
    bool? loadingMore,
    Object? error = _unset,
    int? page,
    int? failedPage,
    bool? exhausted,
  }) {
    return ReplyThread(
      items: items ?? this.items,
      loading: loading ?? this.loading,
      loadingMore: loadingMore ?? this.loadingMore,
      error: identical(error, _unset) ? this.error : error as String?,
      page: page ?? this.page,
      failedPage: failedPage ?? this.failedPage,
      exhausted: exhausted ?? this.exhausted,
    );
  }

  static const _unset = Object();
}
