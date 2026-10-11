import 'package:flutter/material.dart';

/// 加载中占位.
class LoadingWidget extends StatelessWidget {
  const LoadingWidget({super.key, this.height});

  final double? height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}

/// 空状态占位.
class EmptyWidget extends StatelessWidget {
  const EmptyWidget({
    super.key,
    this.message = '这里什么都没有',
    this.icon = Icons.inbox_outlined,
    this.onRetry,
    this.retryText = '重试',
  });

  final String message;
  final IconData icon;
  final VoidCallback? onRetry;
  final String retryText;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: scheme.outline),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onRetry, child: Text(retryText)),
          ],
        ],
      ),
    );
  }
}

/// 错误状态占位.
class ErrorWidgetView extends StatelessWidget {
  const ErrorWidgetView({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return EmptyWidget(
      message: message,
      icon: Icons.error_outline,
      onRetry: onRetry,
      retryText: '重新加载',
    );
  }
}

/// 视频卡片骨架屏, 用于首屏加载时占位.
class VideoCardSkeleton extends StatelessWidget {
  const VideoCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).colorScheme.surfaceContainerHighest;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AspectRatio(
          aspectRatio: 362 / 233,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: base,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        const SizedBox(height: 6),
        _Bar(color: base, width: double.infinity),
        const SizedBox(height: 5),
        _Bar(color: base, width: 90),
      ],
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.color, required this.width});

  final Color color;
  final double width;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: 11,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}
