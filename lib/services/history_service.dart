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

  /// 距离结尾不到这么多秒就算看完, 与播放页从头播放的判断一致.
  static const finishToleranceSeconds = 10.0;

  bool get finished =>
      duration > 0 && duration - progress <= finishToleranceSeconds;

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
    video: VideoModel.fromJson((json['video'] as Map).cast<String, dynamic>()),
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

  /// 每个视频最近一条记录与看过的分P, 列表变化后在下次查询时重建.
  ///
  /// 卡片每次构建都要查一次, 不建索引的话一屏卡片要把 500 条历史扫好几十遍.
  Map<String, HistoryItem>? _latest;
  Map<String, Map<int, HistoryItem>>? _byPart;

  void _invalidate() {
    _latest = null;
    _byPart = null;
  }

  void _buildIndex() {
    final latest = <String, HistoryItem>{};
    final byPart = <String, Map<int, HistoryItem>>{};
    // 列表按时间倒序, 第一次遇到的就是最新的.
    for (final item in list) {
      latest.putIfAbsent(item.video.hid, () => item);
      byPart.putIfAbsent(item.video.hid, () => {})[item.part] = item;
    }
    _latest = latest;
    _byPart = byPart;
  }

  /// 视频最近一次的观看记录, 在 Obx 里调用时会跟着历史变化刷新.
  HistoryItem? latestOf(String hid) {
    // 先读一下列表, 让外层 Obx 订阅到历史变化.
    list.length;
    if (_latest == null) _buildIndex();
    return _latest![hid];
  }

  /// 视频各分P的观看记录, 键是分P序号.
  Map<int, HistoryItem> partsOf(String hid) {
    list.length;
    if (_byPart == null) _buildIndex();
    return _byPart![hid] ?? const {};
  }

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
    _invalidate();
  }

  Future<void> _save() async {
    await GStorage.history.put(_kHistory, list.map((e) => e.toJson()).toList());
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
    _invalidate();
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
    _invalidate();
    await _save();
  }

  Future<void> clear() async {
    list.clear();
    _invalidate();
    await _save();
  }
}
