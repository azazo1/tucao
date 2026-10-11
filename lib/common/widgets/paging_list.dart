import 'package:flutter/material.dart';
import 'package:tucao/common/widgets/loading_widget.dart';
import 'package:tucao/common/widgets/video_card.dart';

/// 支持下拉刷新与上拉加载的列表.
///
/// 站点的列表页结构一致, 这里统一封装, 避免各页面重复处理分页状态.
class PagingList<T> extends StatelessWidget {
  const PagingList({
    super.key,
    required this.list,
    required this.itemBuilder,
    required this.onRefresh,
    required this.onLoadMore,
    required this.hasMore,
    required this.loading,
    this.firstLoading = false,
    this.error,
    this.onRetry,
    this.emptyMessage = '这里什么都没有',
    this.padding = const EdgeInsets.symmetric(horizontal: 12),
    this.separator,
    this.header,
  });

  final List<T> list;
  final Widget Function(BuildContext context, T item, int index) itemBuilder;
  final Future<void> Function() onRefresh;
  final VoidCallback onLoadMore;

  /// 是否还有下一页.
  final bool hasMore;

  /// 是否正在加载下一页.
  final bool loading;

  /// 是否处于首屏加载.
  final bool firstLoading;

  /// 首屏错误信息.
  final String? error;

  final VoidCallback? onRetry;
  final String emptyMessage;
  final EdgeInsets padding;

  /// 列表项之间的分隔.
  final Widget? separator;

  /// 列表顶部固定内容.
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    if (firstLoading) {
      return const LoadingWidget();
    }
    if (error != null && list.isEmpty) {
      return ErrorWidgetView(message: error!, onRetry: onRetry);
    }
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification.metrics.pixels >=
              notification.metrics.maxScrollExtent - 300) {
            if (hasMore && !loading) {
              onLoadMore();
            }
          }
          return false;
        },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            if (header != null)
              SliverToBoxAdapter(child: header)
            else
              const SliverToBoxAdapter(child: SizedBox.shrink()),
            if (list.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyWidget(message: emptyMessage),
              )
            else
              SliverPadding(
                padding: padding,
                sliver: SliverList.separated(
                  itemCount: list.length,
                  separatorBuilder: (context, index) =>
                      separator ?? const SizedBox.shrink(),
                  itemBuilder: (context, index) =>
                      itemBuilder(context, list[index], index),
                ),
              ),
            SliverToBoxAdapter(
              child: LoadMoreFooter(
                loading: loading,
                hasMore: hasMore,
                onRetry: onLoadMore,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
