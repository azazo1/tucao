import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tucao/common/widgets/video_card.dart';
import 'package:tucao/models/video.dart';
import 'package:tucao/pages/video/video_page.dart';
import 'package:tucao/pages/video/widgets/related_videos.dart';
import 'package:tucao/plugin/player/player_controller.dart';
import 'package:tucao/services/block_service.dart';
import 'package:tucao/services/related/related_ranker.dart';
import 'package:tucao/utils/logger.dart';

/// 简介下方的站点系列, 取自播放页右侧的 "视频列表", 排在相关视频前面.
///
/// 只有站点整理过系列的作品才有, 列表里包含当前视频, 标上正在播放,
/// 其余条目点开后在当前播放页之上压入新的播放页.
class SiteSeriesSliver extends StatelessWidget {
  const SiteSeriesSliver({super.key, required this.controller});

  final PlayerPageController controller;

  /// 打开前先暂停当前视频, 被盖住的播放页不会自己停下.
  void _open(VideoModel video) {
    Log.i('从站点系列打开 ${video.hid}');
    controller.player.pause();
    VideoPage.open(video);
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final hidden = <String>{
        for (final item in BlockService.instance.list) item.hid,
      };
      final current = controller.hid;
      final entries = [
        for (final entry in RelatedRanker.sortSeries(controller.siteSeries))
          if (entry.video.hid == current || !hidden.contains(entry.video.hid))
            entry,
      ];
      // 只剩当前视频时没有可跳转的条目, 不占位置.
      if (entries.length < 2) {
        return const SliverToBoxAdapter(child: SizedBox.shrink());
      }
      return SliverPadding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
        sliver: SliverList.builder(
          itemCount: entries.length + 1,
          itemBuilder: (context, index) {
            if (index == 0) {
              return const RelatedSectionHeader('系列');
            }
            final entry = entries[index - 1];
            final playing = entry.video.hid == current;
            return VideoCardHorizontal(
              video: entry.video,
              badge: playing ? '正在播放' : entry.label,
              showDanmaku: false,
              onTap: playing ? () {} : () => _open(entry.video),
            );
          },
        ),
      );
    });
  }
}
