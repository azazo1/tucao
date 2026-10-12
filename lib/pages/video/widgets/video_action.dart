import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tucao/pages/reply/reply_page.dart';
import 'package:tucao/pages/favorite/widgets/favorite_button.dart';
import 'package:tucao/plugin/player/player_controller.dart';
import 'package:tucao/utils/utils.dart';

/// 播放器下方的操作区: 弹幕发送框, 评论与本地收藏入口.
class VideoActionBar extends StatefulWidget {
  const VideoActionBar({super.key, required this.controller, this.onComment});

  final PlayerPageController controller;
  final VoidCallback? onComment;

  @override
  State<VideoActionBar> createState() => _VideoActionBarState();
}

class _VideoActionBarState extends State<VideoActionBar> {
  final _textController = TextEditingController();

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _textController.text;
    if (text.trim().isEmpty) {
      return;
    }
    final error = await widget.controller.sendDanmaku(text);
    if (!mounted) {
      return;
    }
    if (error != null) {
      Get.snackbar(
        '弹幕发送失败',
        error,
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 2),
      );
      return;
    }
    _textController.clear();
    FocusScope.of(context).unfocus();
    Get.snackbar(
      '提示',
      '弹幕已发送',
      snackPosition: SnackPosition.BOTTOM,
      duration: const Duration(seconds: 1),
    );
  }

  void _openReply() {
    Get.to(
      () => ReplyPage(
        typeId: widget.controller.typeId,
        hid: widget.controller.hid,
        part: widget.controller.part.value,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Row(
        children: [
          Expanded(
            child: ListenableBuilder(
              listenable: widget.controller.player,
              builder: (context, child) {
                final position = widget.controller.player.position;
                return TextField(
                  controller: _textController,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  maxLength: 60,
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    isDense: true,
                    counterText: '',
                    hintText: '发个弹幕见证当下 ${Utils.formatDuration(position)}',
                    hintStyle: const TextStyle(fontSize: 13),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 8),
          Obx(
            () => IconButton.filled(
              onPressed: widget.controller.sending.value ? null : _send,
              icon: widget.controller.sending.value
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send, size: 18),
              visualDensity: VisualDensity.compact,
            ),
          ),
          const SizedBox(width: 4),
          IconButton.outlined(
            onPressed: widget.onComment ?? _openReply,
            icon: Icon(Icons.comment_outlined, size: 18, color: scheme.primary),
            visualDensity: VisualDensity.compact,
            tooltip: '评论',
          ),
          Obx(() {
            final video = widget.controller.video.value;
            return video == null
                ? const SizedBox.shrink()
                : FavoriteButton(video: video);
          }),
        ],
      ),
    );
  }
}
