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
        builder: (context, constraints) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Align(
              alignment: Alignment.centerRight,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 340),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
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
                        children: [
                          Expanded(
                            child: ComicSpeechBubble(
                              fill: scheme.surfaceContainerLow,
                              ink: scheme.outlineVariant,
                              child: Text(
                                '谢谢支持,\n回去看番吧~',
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodyMedium,
                              ),
                            ),
                          ),
                          ClipRect(
                            child: Image.asset(
                              CcPeekThanks.stillAsset,
                              width: 148,
                              height: 232,
                              fit: BoxFit.fill,
                              excludeFromSemantics: true,
                              errorBuilder: (_, error, stack) => const SizedBox(
                                width: 148,
                                height: 232,
                                child: Icon(Icons.favorite_outline, size: 48),
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
        ),
      ),
    );
  }
}
