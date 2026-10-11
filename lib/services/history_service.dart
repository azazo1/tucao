import 'package:get/get.dart';
import 'package:tucao/models/video.dart';
import 'package:tucao/utils/storage.dart';

/// 播放历史条目.
class HistoryItem {
  const HistoryItem({
    required this.video,
    required this.part,
    required this.progress,
    required this.duration,
    required this.updateTime,
  });

  final VideoModel video;

  /// 分P序号, 从 0 开始.
  final int part;

  /// 播放进度, 秒.
  final double progress;

  /// 视频总时长, 秒.
  final double duration;

  /// 记录更新时间, 毫秒时间戳.
  final int updateTime;

  double get percent => duration <= 0 ? 0 : (progress / duration).clamp(0, 1);

  Map<String, dynamic> toJson() => {
    'video': {
      'hid': video.hid,
      'title': video.title,
      'typeid': video.typeId.toString(),
      'typename': video.typeName,
      'thumb': video.cover,
      'play': video.playCount.toString(),
      'mukio': video.danmakuCount.toString(),
      'create': video.createTime.toString(),
      'user': video.userName,
      'userid': video.userId.toString(),
      'part': video.partCount,
    },
    'part': part,
    'progress': progress,
    'duration': duration,
    'updateTime': updateTime,
  };

  factory HistoryItem.fromJson(Map<String, dynamic> json) => HistoryItem(
    video: VideoModel.fromJson(
      (json['video'] as Map).cast<String, dynamic>(),
    ),
    part: (json['part'] as num?)?.toInt() ?? 0,
    progress: (json['progress'] as num?)?.toDouble() ?? 0,
    duration: (json['duration'] as num?)?.toDouble() ?? 0,
    updateTime: (json['updateTime'] as num?)?.toInt() ?? 0,
  );
}

/// 播放历史.
///
/// 站点不提供稳定的历史接口, 因此保存在本地.
class HistoryService extends GetxController {
  static HistoryService get instance => Get.find<HistoryService>();

  static const _kHistory = 'history';
  static const _maxCount = 500;

  final list = <HistoryItem>[].obs;

  @override
  void onInit() {
    super.onInit();
    _load();
  }

  void _load() {
    final raw = GStorage.history.get(_kHistory);
    if (raw is List) {
      list.assignAll(
        raw
            .whereType<Map>()
            .map((e) => HistoryItem.fromJson(e.cast<String, dynamic>()))
            .toList(),
      );
    }
  }

  Future<void> _save() async {
    await GStorage.history.put(
      _kHistory,
      list.map((e) => e.toJson()).toList(),
    );
  }

  /// 记录进度, 同一视频同一分P只保留最新一条.
  Future<void> record({
    required VideoModel video,
    required int part,
    required double progress,
    required double duration,
  }) async {
    list.removeWhere((e) => e.video.hid == video.hid && e.part == part);
    list.insert(
      0,
      HistoryItem(
        video: video,
        part: part,
        progress: progress,
        duration: duration,
        updateTime: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    if (list.length > _maxCount) {
      list.removeRange(_maxCount, list.length);
    }
    await _save();
  }

  /// 查询某个视频上次播放到的位置.
  HistoryItem? find(String hid, int part) {
    for (final item in list) {
      if (item.video.hid == hid && item.part == part) {
        return item;
      }
    }
    return null;
  }

  Future<void> remove(HistoryItem item) async {
    list.remove(item);
    await _save();
  }

  Future<void> clear() async {
    list.clear();
    await _save();
  }
}
