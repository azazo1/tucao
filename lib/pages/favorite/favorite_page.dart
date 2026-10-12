import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tucao/common/widgets/loading_widget.dart';
import 'package:tucao/common/widgets/video_card.dart';
import 'package:tucao/models/favorite.dart';
import 'package:tucao/pages/video/video_page.dart';
import 'package:tucao/services/favorite_service.dart';

/// 收藏与官方客户端一样仅保存在此设备, 不与站点账号同步.
class FavoritePage extends StatefulWidget {
  const FavoritePage({super.key});

  @override
  State<FavoritePage> createState() => _FavoritePageState();
}

class _FavoritePageState extends State<FavoritePage> {
  final _removing = <String>{};
  final _saving = <String>{};
  bool get _current => mounted && ModalRoute.of(context)?.isCurrent == true;

  Future<void> _remove(FavoriteItem item) async {
    if (_removing.contains(item.video.hid) || !_current) {
      return;
    }
    setState(() => _removing.add(item.video.hid));
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('取消本地收藏'),
          content: Text('将从此设备的收藏中移除 ${item.video.title}, 确定继续吗?'),
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
      if (confirmed == true && _current) {
        setState(() => _saving.add(item.video.hid));
        await FavoriteService.instance.remove(item.video.hid);
      }
    } catch (error) {
      if (mounted && _current) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('取消本地收藏失败: $error')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _removing.remove(item.video.hid);
          _saving.remove(item.video.hid);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = FavoriteService.instance;
    return Scaffold(
      appBar: AppBar(title: const Text('本地收藏')),
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text('仅保存在此设备, 无需登录, 不与站点账号同步'),
          ),
          Expanded(child: Obx(() {
            if (service.loadError.value != null) {
              return ErrorWidgetView(
                message: service.loadError.value!,
                onRetry: service.reload,
              );
            }
            if (service.list.isEmpty) {
              return const EmptyWidget(
                message: '还没有本地收藏', icon: Icons.favorite_border,
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: service.list.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final item = service.list[index];
                final busy = _removing.contains(item.video.hid);
                return Row(
                  key: ValueKey('favorite-${item.video.hid}'),
                  children: [
                    Expanded(child: VideoCardHorizontal(
                      video: item.video,
                      onTap: () => VideoPage.open(item.video),
                    )),
                    IconButton(
                      key: ValueKey('favorite-remove-${item.video.hid}'),
                      tooltip: '取消本地收藏',
                      onPressed: busy ? null : () => _remove(item),
                      icon: _saving.contains(item.video.hid)
                          ? const SizedBox(width: 18, height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.favorite),
                    ),
                  ],
                );
              },
            );
          })),
        ],
      ),
    );
  }
}
