import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tucao/models/video.dart';
import 'package:tucao/services/favorite_service.dart';

/// 独立详情入口, 本地收藏不要求登录, 不与站点账号同步.
class FavoriteButton extends StatefulWidget {
  const FavoriteButton({super.key, required this.video});

  final VideoModel video;

  @override
  State<FavoriteButton> createState() => _FavoriteButtonState();
}

class _FavoriteButtonState extends State<FavoriteButton> {
  bool _busy = false;
  bool _saving = false;
  bool get _current => mounted && ModalRoute.of(context)?.isCurrent == true;

  Future<void> _toggle() async {
    if (_busy || !_current) {
      return;
    }
    final service = FavoriteService.instance;
    final video = widget.video;
    setState(() => _busy = true);
    try {
      if (service.contains(video.hid)) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('取消本地收藏'),
            content: Text('将从此设备的收藏中移除 ${video.title}, 确定继续吗?'),
            actions: [
              TextButton(
                key: const ValueKey('favorite-cancel'),
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('保留'),
              ),
              FilledButton(
                key: const ValueKey('favorite-confirm'),
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('取消收藏'),
              ),
            ],
          ),
        );
        if (confirmed != true || !_current) {
          return;
        }
        setState(() => _saving = true);
        await service.remove(video.hid);
      } else {
        setState(() => _saving = true);
        await service.add(video);
      }
    } catch (error) {
      if (mounted && _current) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('本地收藏保存失败: $error')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = FavoriteService.instance;
    return Obx(() {
      final selected = service.contains(widget.video.hid);
      return IconButton.outlined(
        key: const ValueKey('favorite-toggle'),
        isSelected: selected,
        tooltip: selected ? '已本地收藏' : '本地收藏',
        iconSize: 18,
        visualDensity: VisualDensity.compact,
        onPressed: _busy || widget.video.hid.isEmpty ||
            service.loadError.value != null ? null : _toggle,
        icon: _saving
            ? const SizedBox(width: 18, height: 18,
                child: CircularProgressIndicator(strokeWidth: 2))
            : Icon(selected ? Icons.favorite : Icons.favorite_border),
      );
    });
  }
}
