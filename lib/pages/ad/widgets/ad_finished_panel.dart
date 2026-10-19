import 'package:flutter/material.dart';
import 'package:tucao/common/widgets/cc/cc_peek_thanks.dart';
import 'package:tucao/common/widgets/cc/comic_speech_bubble.dart';

/// 广告列表为空时的静态感谢, 不推断是否在其他设备看完或今日配额.
/// 不播放或重播动画, 也不增加与顶栏重复的返回按钮.
class AdFinishedPanel extends StatelessWidget {
  const AdFinishedPanel({super.key, this.completedHere = false});

  final bool completedHere;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SafeArea(
      top: false,
      right: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // 横屏等矮屏下按可用高度缩小, 不让图片被滚动容器裁掉.
          final labelSpace = completedHere ? 52.0 : 0.0;
          final imageHeight = (constraints.maxHeight - labelSpace - 40)
              .clamp(120.0, 232.0)
              .toDouble();
          final imageWidth = imageHeight * 148 / 232;
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Align(
                alignment: Alignment.bottomRight,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 340),
                  child: Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (completedHere) ...[
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: Text(
                              '本次广告已看完',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                        ],
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(
                              child: Padding(
                                // 气泡不压到屏幕底部, 人物则贴着底边.
                                padding: const EdgeInsets.only(bottom: 24),
                                child: ComicSpeechBubble(
                                  tail: ComicBubbleTail.right,
                                  fill: scheme.surfaceContainerLow,
                                  ink: scheme.outlineVariant,
                                  child: Text(
                                    '谢谢支持,\n回去看番吧~',
                                    textAlign: TextAlign.center,
                                    style: theme.textTheme.bodyMedium,
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(
                              width: imageWidth,
                              height: imageHeight,
                              child: ShaderMask(
                                blendMode: BlendMode.dstIn,
                                shaderCallback: (rect) => LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: const [
                                    Colors.white,
                                    Colors.white,
                                    Colors.transparent,
                                  ],
                                  stops: const [0, 0.86, 1],
                                ).createShader(rect),
                                child: Image.asset(
                                  CcPeekThanks.stillAsset,
                                  fit: BoxFit.fill,
                                  excludeFromSemantics: true,
                                  errorBuilder: (_, error, stack) => const Icon(
                                    Icons.favorite_outline,
                                    size: 48,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
