import 'dart:async';

import 'package:canvas_danmaku/canvas_danmaku.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tucao/http/danmaku_http.dart';
import 'package:tucao/http/video_http.dart';
import 'package:tucao/models/danmaku.dart';
import 'package:tucao/models/video.dart';
import 'package:tucao/plugin/player/tucao_player.dart';
import 'package:tucao/services/account_service.dart';
import 'package:tucao/services/history_service.dart';
import 'package:tucao/utils/date_utils.dart';
import 'package:tucao/utils/logger.dart';
import 'package:tucao/utils/storage_pref.dart';

/// 播放页控制器.
///
/// 负责视频详情, 分P选择, 弹幕拉取与投递, 播放历史.
/// 播放本身交给 [TucaoPlayer].
class PlayerPageController extends GetxController {
  PlayerPageController({required this.hid, int part = 0, VideoModel? initial})
    : _initialPart = part,
      _initial = initial;

  /// 视频 id.
  final String hid;

  final int _initialPart;

  /// 从列表页带过来的数据, 用于首屏立即展示标题.
  final VideoModel? _initial;

  final player = TucaoPlayer();

  /// 视频详情, 加载完成前可能只有列表页带过来的简要信息.
  final video = Rxn<VideoModel>();

  /// 当前分P序号, 从 0 开始.
  final part = 0.obs;

  final firstLoading = true.obs;

  final error = RxnString();

  /// 当前分P的播放地址, 为空表示没有可用地址.
  final playUrl = ''.obs;

  /// 视频源失效等提示.
  final sourceError = RxnString();

  final danmakuEnabled = Pref.danmakuEnable.obs;

  final sending = false.obs;

  /// 记录进度的间隔.
  static const _historyInterval = Duration(seconds: 5);

  /// 位置跳变超过该秒数时视为拖动进度, 需要重定位弹幕.
  static const _seekTolerance = 1.0;

  /// 续播的最小进度, 太靠前没有意义.
  static const _minResumeSeconds = 5.0;

  /// 距离结尾这么近时从头播放.
  static const _endToleranceSeconds = 10.0;

  List<DanmakuModel> _danmaku = const [];

  /// 下一条待投递弹幕的下标.
  int _nextDanmaku = 0;

  /// 上一次的播放位置, 秒.
  double _lastPosition = -1;

  bool _lastPlaying = false;

  DanmakuController<DanmakuModel>? _danmakuController;

  Timer? _historyTimer;

  List<VideoPart> get parts => video.value?.parts ?? const [];

  int get partCount => parts.isEmpty ? 1 : parts.length;

  /// 当前分P是否为第三方源.
  bool get isThirdParty {
    final index = part.value;
    final list = parts;
    if (index < 0 || index >= list.length) {
      return true;
    }
    return list[index].isThirdParty;
  }

  Duration get position => player.position;

  Duration get duration => player.duration;

  @override
  void onInit() {
    super.onInit();
    video.value = _initial;
    part.value = _initialPart;
    player.addListener(_onPlayerChanged);
    _historyTimer = Timer.periodic(_historyInterval, (_) => recordHistory());
    load();
  }

  @override
  void onClose() {
    _historyTimer?.cancel();
    _historyTimer = null;
    // 退出前再记一次, 不等待写入完成.
    unawaited(recordHistory());
    player.removeListener(_onPlayerChanged);
    player.dispose();
    _danmakuController = null;
    super.onClose();
  }

  /// 拉取视频详情并加载当前分P.
  Future<void> load() async {
    firstLoading.value = true;
    error.value = null;
    try {
      final response = await VideoHttp.view(hid: hid);
      if (!response.success || response.result == null) {
        error.value = response.message ?? '视频加载失败';
        return;
      }
      video.value = response.result;
      final index = part.value.clamp(0, partCount - 1);
      await _loadPart(index, resume: true);
    } catch (e, stackTrace) {
      Log.e('加载视频详情失败', error: e, stackTrace: stackTrace);
      error.value = '视频加载失败, 请稍后重试';
    } finally {
      firstLoading.value = false;
    }
  }

  /// 切换分P.
  Future<void> switchPart(int index) async {
    if (index < 0 || index >= partCount || index == part.value) {
      return;
    }
    // 先记下当前分P的进度, 避免切走后丢失.
    await recordHistory();
    await _loadPart(index, resume: false);
  }

  Future<void> _loadPart(int index, {required bool resume}) async {
    part.value = index;
    sourceError.value = null;
    playUrl.value = '';
    _resetDanmaku();

    final list = parts;
    final target = index >= 0 && index < list.length ? list[index] : null;
    final url = target?.file ?? '';
    if (target == null || url.isEmpty) {
      // 第三方源已经不再提供播放地址, 这里只给出提示.
      sourceError.value = '该视频源已失效';
      Log.w('分P ${index + 1} 没有可播放地址, vid=${target?.vid}');
      await player.stop();
      return;
    }
    playUrl.value = url;

    final danmakuFuture = _loadDanmaku(index);
    final startAt = resume ? _resumePosition(index) : null;
    try {
      await player.setUrl(
        url,
        autoPlay: Pref.playerAutoPlay,
        startAt: startAt,
      );
      if (startAt != null) {
        Log.i('续播上次进度 ${startAt.inSeconds}s');
      }
    } catch (e, stackTrace) {
      Log.e('播放地址加载失败', error: e, stackTrace: stackTrace);
      sourceError.value = '播放失败, 请切换分P或稍后重试';
    }
    await danmakuFuture;
  }

  /// 查询上次播放位置, 不满足续播条件时返回空.
  Duration? _resumePosition(int index) {
    if (!Pref.playerContinueLast) {
      return null;
    }
    final item = HistoryService.instance.find(hid, index);
    if (item == null) {
      return null;
    }
    final progress = item.progress;
    final total = item.duration;
    if (progress < _minResumeSeconds) {
      return null;
    }
    if (total > 0 && progress > total - _endToleranceSeconds) {
      return null;
    }
    return Duration(milliseconds: (progress * 1000).round());
  }

  Future<void> _loadDanmaku(int index) async {
    try {
      final list = await DanmakuHttp.fetch(hid: hid, part: index);
      list.sort((a, b) => a.time.compareTo(b.time));
      _danmaku = list;
      Log.i('分P ${index + 1} 加载弹幕 ${list.length} 条');
    } catch (e, stackTrace) {
      Log.e('弹幕加载失败', error: e, stackTrace: stackTrace);
      _danmaku = const [];
    }
  }

  /// 挂载弹幕渲染器, 页面创建 [DanmakuScreen] 后调用.
  void attachDanmaku(DanmakuController<DanmakuModel> controller) {
    _danmakuController = controller;
    _lastPosition = -1;
    _nextDanmaku = 0;
    _lastPlaying = player.playing;
    if (!danmakuEnabled.value || !player.playing) {
      controller.pause();
    }
  }

  /// 页面销毁时解绑.
  void detachDanmaku() {
    _danmakuController = null;
  }

  /// 弹幕渲染配置, 全部来自用户偏好.
  DanmakuOption get danmakuOption => DanmakuOption(
    fontSize: Pref.danmakuFontSize,
    area: Pref.danmakuArea,
    // 站点设置里的弹幕速度是滚动弹幕穿过屏幕的秒数.
    duration: Pref.danmakuSpeed,
    opacity: Pref.danmakuOpacity,
    strokeWidth: Pref.danmakuStroke,
    hideScroll: Pref.danmakuHideScroll,
    hideTop: Pref.danmakuHideTop,
    hideBottom: Pref.danmakuHideBottom,
  );

  /// 把偏好同步给渲染器, 用于设置变更后立即生效.
  void applyDanmakuOption() {
    _danmakuController?.updateOption(danmakuOption);
  }

  void toggleDanmaku() {
    final enabled = !danmakuEnabled.value;
    danmakuEnabled.value = enabled;
    Pref.danmakuEnable = enabled;
    final controller = _danmakuController;
    if (controller == null) {
      return;
    }
    if (enabled) {
      if (player.playing) {
        controller.resume();
      }
    } else {
      controller.clear();
      controller.pause();
    }
  }

  Future<void> togglePlay() async {
    if (player.completed) {
      await player.seek(Duration.zero);
      await player.play();
      _resetDanmaku();
      return;
    }
    await player.toggle();
  }

  Future<void> seek(Duration position) async {
    await player.seek(position);
  }

  Future<void> setSpeed(double speed) async {
    await player.setSpeed(speed);
  }

  /// 发送弹幕, 成功返回空, 失败返回提示文本.
  Future<String?> sendDanmaku(String text) async {
    final content = text.trim();
    if (content.isEmpty) {
      return '弹幕内容不能为空';
    }
    if (!AccountService.instance.isLogin) {
      return '请先登录后再发送弹幕';
    }
    final current = video.value;
    if (current == null) {
      return '视频信息还没加载好';
    }
    final time = player.position.inMilliseconds / 1000;
    sending.value = true;
    try {
      final raw = await DanmakuHttp.send(
        hid: hid,
        part: part.value,
        text: content,
        time: time,
      );
      final result = _parseSendResult(raw);
      if (result != null) {
        return result;
      }
      // 站点不返回弹幕内容, 本地先按默认样式显示一条.
      final item = DanmakuModel(
        time: time,
        mode: 1,
        fontSize: 25,
        color: 0xFFFFFF,
        timestamp: DateUtil.nowSeconds(),
        text: content,
      );
      _danmakuController?.addDanmaku(_toContentItem(item));
      Log.i('弹幕发送成功: $content');
      return null;
    } catch (e, stackTrace) {
      Log.e('弹幕发送失败', error: e, stackTrace: stackTrace);
      return '弹幕发送失败, 请稍后重试';
    } finally {
      sending.value = false;
    }
  }

  /// 站点成功时返回 1 或提示文本, 失败时返回错误说明.
  String? _parseSendResult(String raw) {
    final text = raw.replaceAll(RegExp(r'<[^>]*>'), '').trim();
    if (text.isEmpty || text == '1' || text.contains('成功')) {
      return null;
    }
    if (text.contains('登录') || text.contains('登陆')) {
      return '请先登录后再发送弹幕';
    }
    Log.w('弹幕接口返回: $text');
    return text.length > 40 ? '弹幕发送失败' : text;
  }

  /// 写入播放历史.
  Future<void> recordHistory() async {
    final current = video.value;
    if (current == null) {
      return;
    }
    final total = player.duration.inMilliseconds / 1000;
    if (total <= 0) {
      return;
    }
    final progress = player.position.inMilliseconds / 1000;
    try {
      await HistoryService.instance.record(
        video: current,
        part: part.value,
        progress: progress,
        duration: total,
      );
    } catch (e, stackTrace) {
      Log.e('写入播放历史失败', error: e, stackTrace: stackTrace);
    }
  }

  void _onPlayerChanged() {
    _syncDanmaku();
  }

  /// 按播放位置投递弹幕, 而不是一次性全部交给渲染器.
  void _syncDanmaku() {
    final controller = _danmakuController;
    if (controller == null) {
      return;
    }
    final playing = player.playing;
    if (playing != _lastPlaying) {
      _lastPlaying = playing;
      if (playing) {
        if (danmakuEnabled.value) {
          controller.resume();
        }
      } else {
        controller.pause();
      }
    }
    if (!danmakuEnabled.value) {
      return;
    }
    final current = player.position.inMilliseconds / 1000;
    if (_lastPosition >= 0 &&
        (current - _lastPosition).abs() > _seekTolerance) {
      // 拖动进度后重新定位, 已经飘过的弹幕不再补投.
      controller.clear();
      _nextDanmaku = _lowerBound(current);
    }
    _lastPosition = current;
    while (_nextDanmaku < _danmaku.length &&
        _danmaku[_nextDanmaku].time <= current) {
      controller.addDanmaku(_toContentItem(_danmaku[_nextDanmaku]));
      _nextDanmaku++;
    }
  }

  void _resetDanmaku() {
    _danmaku = const [];
    _nextDanmaku = 0;
    _lastPosition = -1;
    _danmakuController?.clear();
  }

  /// 找到第一条不早于 [time] 的弹幕下标.
  int _lowerBound(double time) {
    var low = 0;
    var high = _danmaku.length;
    while (low < high) {
      final mid = (low + high) >> 1;
      if (_danmaku[mid].time < time) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low;
  }

  DanmakuContentItem<DanmakuModel> _toContentItem(DanmakuModel model) {
    return DanmakuContentItem<DanmakuModel>(
      model.text,
      color: Color(model.color | 0xFF000000),
      type: _typeOf(model.mode),
      extra: model,
    );
  }

  /// 站点弹幕类型: 1 2 3 滚动, 4 底部, 5 顶部, 7 高级弹幕.
  /// 高级弹幕站点早已不再产生, 统一按滚动处理.
  DanmakuItemType _typeOf(int mode) {
    return switch (mode) {
      4 => DanmakuItemType.bottom,
      5 => DanmakuItemType.top,
      _ => DanmakuItemType.scroll,
    };
  }
}
