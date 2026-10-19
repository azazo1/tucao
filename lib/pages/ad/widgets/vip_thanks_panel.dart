import 'package:flutter/material.dart';
import 'package:tucao/common/widgets/cc/cc_thanks_animation.dart';
import 'package:tucao/common/widgets/cc/comic_speech_bubble.dart';
import 'package:tucao/utils/logger.dart';

/// 只确认当前应用广告页的免广告状态, 不承诺站点或外链广告权益.
class VipThanksPanel extends StatefulWidget {
  const VipThanksPanel({super.key});

  @override
  State<VipThanksPanel> createState() => _VipThanksPanelState();
}

class _VipThanksPanelState extends State<VipThanksPanel> {
  int _replay = 0;

  @override
  void initState() {
    super.initState();
    Log.i('广告页展示破会员感谢页, 不加载广告列表');
  }

  void _replayThanks() {
    Log.d('重播 CC 娘感谢动画');
    setState(() => _replay++);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return SafeArea(
      top: false,
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: constraints.maxHeight > 48
                  ? constraints.maxHeight - 48
                  : 0,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ComicSpeechBubble(
                      fill: scheme.surfaceContainerLow,
                      ink: scheme.outlineVariant,
                      child: Text(
                        '谢谢支持,\n今天也要看得开心~',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: scheme.onSurface,
                          height: 1.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: 208,
                      child: Tooltip(
                        message: reduceMotion ? 'CC 娘' : '点击 CC 娘重播感谢动画',
                        excludeFromSemantics: true,
                        child: Semantics(
                          label: 'CC 娘感谢你支持小站',
                          button: !reduceMotion,
                          image: reduceMotion,
                          hint: reduceMotion ? null : '点击重播感谢动画',
                          onTap: reduceMotion ? null : _replayThanks,
                          child: ExcludeSemantics(
                            child: InkWell(
                              key: const ValueKey('cc-thanks-replay'),
                              onTap: reduceMotion ? null : _replayThanks,
                              borderRadius: BorderRadius.circular(104),
                              child: CcThanksAnimation(replay: _replay),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '破会员已免广告',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
