import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tucao/common/widgets/video_card.dart';
import 'package:tucao/models/video.dart';
import 'package:tucao/pages/video/video_page.dart';
import 'package:tucao/plugin/player/player_controller.dart';
import 'package:tucao/services/block_service.dart';
import 'package:tucao/services/related/related_ranker.dart';
import 'package:tucao/services/related/related_service.dart';
import 'package:tucao/utils/logger.dart';
import 'package:tucao/utils/storage_pref.dart';

/// 简介最下方的相关视频列表, 以 sliver 形式接在简介内容后面.
///
/// 每张卡片是一个投稿, 点开后在当前播放页之上压入新的播放页,
/// 返回即回到这里.
class RelatedVideosSliver extends StatefulWidget {
  const RelatedVideosSliver({super.key, required this.controller});

  final PlayerPageController controller;

  @override
  State<RelatedVideosSliver> createState() => _RelatedVideosSliverState();
}

class _RelatedVideosSliverState extends State<RelatedVideosSliver> {
  /// 设置项只在进入页面时读一次, 改了设置后下次打开播放页生效.
  late final bool _enabled = Pref.showRelatedVideos;

  List<RelatedEntry>? _entries;
  bool _loading = false;
  bool _failed = false;

  /// 已经请求过的视频, 详情刷新时同一视频不重复请求.
  String? _loadedHid;

  Worker? _videoWorker;

  @override
  void initState() {
    super.initState();
    if (!_enabled) {
      return;
    }
    _videoWorker = ever<VideoModel?>(widget.controller.video, _onVideo);
    _onVideo(widget.controller.video.value);
  }

  @override
  void dispose() {
    _videoWorker?.dispose();
    super.dispose();
  }

  void _onVideo(VideoModel? video) {
    if (video == null || video.hid == _loadedHid) {
      return;
    }
    _loadedHid = video.hid;
    _load(video);
  }

  Future<void> _load(VideoModel video) async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final entries = await RelatedService.load(video);
      if (!mounted || video.hid != _loadedHid) {
        return;
      }
      setState(() {
        _entries = entries;
        _loading = false;
      });
    } catch (e, stackTrace) {
      Log.e('加载相关视频失败', error: e, stackTrace: stackTrace);
      if (!mounted || video.hid != _loadedHid) {
        return;
      }
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  void _retry() {
    final video = widget.controller.video.value;
    if (video != null) {
      _load(video);
    }
  }

  /// 打开前先暂停当前视频, 被盖住的播放页不会自己停下.
  void _open(VideoModel video) {
    Log.i('从相关视频打开 ${video.hid}');
    widget.controller.player.pause();
    VideoPage.open(video);
  }

  @override
  Widget build(BuildContext context) {
    if (!_enabled) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
    if (_loading) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 20),
          child: Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
      );
    }
    if (_failed) {
      return SliverToBoxAdapter(
        child: Center(
          child: TextButton(
            onPressed: _retry,
            child: const Text('相关视频加载失败, 点击重试'),
          ),
        ),
      );
    }
    final entries = _entries;
    if (entries == null || entries.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
    // 在 Obx 里过滤, 屏蔽或解除屏蔽后列表跟着刷新.
    return Obx(() {
      final hidden = <String>{
        for (final item in BlockService.instance.list) item.hid,
      };
      final visible = [
        for (final entry in entries)
          if (!hidden.contains(entry.video.hid)) entry,
      ];
      if (visible.isEmpty) {
        return const SliverToBoxAdapter(child: SizedBox.shrink());
      }
      return SliverPadding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        sliver: SliverList.builder(
          itemCount: visible.length + 1,
          itemBuilder: (context, index) {
            if (index == 0) {
              return const _Header();
            }
            final entry = visible[index - 1];
            return VideoCardHorizontal(
              video: entry.video,
              badge: entry.label,
              onTap: () => _open(entry.video),
            );
          },
        ),
      );
    });
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Text(
        '相关视频',
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
