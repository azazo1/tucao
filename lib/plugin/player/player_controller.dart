import 'dart:async';

import 'package:canvas_danmaku/canvas_danmaku.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tucao/http/danmaku_http.dart';
import 'package:tucao/http/video_http.dart';
import 'package:tucao/models/api_response.dart';
import 'package:tucao/models/danmaku.dart';
import 'package:tucao/models/danmaku_preferences.dart';
import 'package:tucao/models/video.dart';
import 'package:tucao/plugin/player/tucao_player.dart';
import 'package:tucao/services/account_service.dart';
import 'package:tucao/services/history_service.dart';
import 'package:tucao/utils/date_utils.dart';
import 'package:tucao/utils/danmaku_preferences_store.dart';
import 'package:tucao/utils/logger.dart';
import 'package:tucao/utils/storage_pref.dart';

/// 播放页控制器.
///
/// 负责视频详情, 分P选择, 弹幕拉取与投递, 播放历史.
/// 播放本身交给 [TucaoPlayer].
class PlayerPageController extends GetxController with WidgetsBindingObserver {
  PlayerPageController({
    required this.hid,
    int part = 0,
    VideoModel? initial,
    TucaoPlayer? player,
    Future<ApiResponse<VideoModel>> Function(String)? loadVideo,
    Future<List<DanmakuModel>> Function(int, String, int)? loadDanmaku,
  }) : _initialPart = part,
       _initial = initial,
       player = player ?? TucaoPlayer(),
       _loadVideo = loadVideo ?? ((hid) => VideoHttp.view(hid: hid)),
       _fetchDanmaku =
           loadDanmaku ??
           ((typeId, hid, part) =>
               DanmakuHttp.fetch(typeId: typeId, hid: hid, part: part));

  /// 视频 id.
  final String hid;

  final int _initialPart;

  /// 从列表页带过来的数据, 用于首屏立即展示标题.
  final VideoModel? _initial;

  final TucaoPlayer player;
  final Future<ApiResponse<VideoModel>> Function(String) _loadVideo;
  final Future<List<DanmakuModel>> Function(int, String, int) _fetchDanmaku;
  final _requests = PlayerRequestGate();
  bool _closed = false;
  AppLifecycleState? _appLifecycleState =
      WidgetsBinding.instance.lifecycleState;

  bool get _playbackAllowed =>
      Pref.playerBackground ||
      _appLifecycleState == null ||
      _appLifecycleState == AppLifecycleState.resumed;

  // 原生播放器实际打开的分P, 不把旧播放进度记入新选择.
  int? _playingPart;

  /// 视频详情, 加载完成前可能只有列表页带过来的简要信息.
  final video = Rxn<VideoModel>();

  /// 当前分P序号, 从 0 开始.
  final part = 0.obs;

  final firstLoading = true.obs;

  final error = RxnString();

  /// 当前分P的播放地址, 为空表示没有可用地址.
  final playUrl = ''.obs;

  /// 播放器是否已经挂载画面, 界面据此决定何时显示视频.
  final playerReady = false.obs;

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

  /// 上一次的播放状态, 用于识别暂停动作.
  bool _wasPlaying = false;

  DanmakuController<DanmakuModel>? _danmakuController;
  DanmakuPreferences? _danmakuPreferences;
  StreamSubscription<DanmakuPreferences>? _danmakuPreferenceChanges;

  Timer? _historyTimer;

  List<VideoPart> get parts => video.value?.parts ?? const [];

  /// 视频所在分区, 弹幕与评论的接口 id 都包含它.
  int get typeId => video.value?.typeId ?? 0;

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

  @override
  void onInit() {
    super.onInit();
    _appLifecycleState = WidgetsBinding.instance.lifecycleState;
    WidgetsBinding.instance.addObserver(this);
    video.value = _initial;
    part.value = _initialPart;
    player.addListener(_onPlayerChanged);
    applyDanmakuPreferences(DanmakuPreferencesStore.read());
    _danmakuPreferenceChanges = DanmakuPreferencesStore.watch().listen(
      applyDanmakuPreferences,
    );
    // 播放到结尾时记一次完整进度, 下次进入从头开始.
    player.onCompleted = () => unawaited(recordHistory());
    _historyTimer = Timer.periodic(_historyInterval, (_) => _tickHistory());
    load();
  }

  @override
  void onClose() {
    _closed = true;
    unawaited(_danmakuPreferenceChanges?.cancel());
    _danmakuPreferenceChanges = null;
    WidgetsBinding.instance.removeObserver(this);
    _requests.close();
    _historyTimer?.cancel();
    _historyTimer = null;
    // 退出前再记一次, 不等待写入完成.
    unawaited(recordHistory());
    player.removeListener(_onPlayerChanged);
    player.onCompleted = null;
    player.dispose();
    _danmakuController = null;
    super.onClose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appLifecycleState = state;
    if (_closed || _playbackAllowed) {
      return;
    }
    // 等待在途 open, 执行前重查代次和前台状态, 不暂停后来的请求.
    unawaited(
      _requests
          .run(_requests.current, () async {
            if (!_playbackAllowed) {
              await player.pause();
            }
          })
          .catchError((Object error, StackTrace stackTrace) {
            if (!_closed) {
              Log.e('后台暂停播放器失败', error: error, stackTrace: stackTrace);
            }
          }),
    );
  }

  /// 定时记录, 只在播放中写, 暂停时位置不会变.
  void _tickHistory() {
    if (player.playing) {
      unawaited(recordHistory());
    }
  }

  /// 拉取视频详情并加载当前分P.
  Future<void> load() async {
    if (_closed) {
      return;
    }
    final request = _requests.begin();
    firstLoading.value = true;
    error.value = null;
    try {
      final response = await _loadVideo(hid);
      if (!_requests.isCurrent(request)) {
        return;
      }
      if (!response.success || response.result == null) {
        error.value = response.message ?? '视频加载失败';
        return;
      }
      video.value = response.result;
      final index = part.value.clamp(0, partCount - 1);
      await _loadPart(index, resume: true, request: request);
    } catch (e, stackTrace) {
      if (_requests.isCurrent(request)) {
        Log.e('加载视频详情失败', error: e, stackTrace: stackTrace);
        error.value = '视频加载失败, 请稍后重试';
      }
    } finally {
      if (_requests.isCurrent(request)) {
        firstLoading.value = false;
      }
    }
  }

  /// 切换分P.
  Future<void> switchPart(int index) async {
    if (_closed || index < 0 || index >= partCount || index == part.value) {
      return;
    }
    final request = _requests.begin();
    // 历史写入先捕获旧进度, 新选择立刻生效, 不等待磁盘写入.
    final history = recordHistory();
    part.value = index;
    firstLoading.value = false;
    error.value = null;
    await history;
    if (_requests.isCurrent(request)) {
      await _loadPart(index, resume: false, request: request);
    }
  }

  Future<void> _loadPart(
    int index, {
    required bool resume,
    required int request,
  }) async {
    if (!_requests.isCurrent(request)) {
      return;
    }
    part.value = index;
    sourceError.value = null;
    playUrl.value = '';
    playerReady.value = false;
    _resetDanmaku();

    final list = parts;
    final target = index >= 0 && index < list.length ? list[index] : null;
    final url = target?.file ?? '';
    if (target == null || url.isEmpty) {
      sourceError.value = '该视频源已失效';
      Log.w('分P ${index + 1} 没有可播放地址, vid=${target?.vid}');
      await _requests.run(request, () async {
        _playingPart = null;
        await player.stop();
      });
      return;
    }

    final danmakuFuture = _loadDanmaku(index, request);
    final startAt = resume ? _resumePosition(index) : null;
    try {
      // 整段原生加载串行执行, 排队中的过期请求直接跳过.
      await _requests.run(request, () async {
        _playingPart = null;
        await player.init();
        if (!_requests.isCurrent(request)) {
          return;
        }
        playUrl.value = url;
        playerReady.value = true;
        await player.setUrl(
          url,
          autoPlay: Pref.playerAutoPlay && _playbackAllowed,
          startAt: startAt,
        );
        // open 期间也可能退到后台. 此时串行区内仍是本次实际媒体,
        // 即使选择已换代也先暂停, 不把暂停排到新媒体打开之后.
        if (!_closed && !_playbackAllowed) {
          await player.pause();
        }
        if (!_requests.isCurrent(request)) {
          return;
        }
        _playingPart = index;
        if (startAt != null) {
          Log.i('续播上次进度 ${startAt.inSeconds}s');
        }
      });
    } catch (e, stackTrace) {
      if (_requests.isCurrent(request)) {
        Log.e('播放地址加载失败', error: e, stackTrace: stackTrace);
        sourceError.value = '播放失败, 请切换分P或稍后重试';
      }
    }
    await danmakuFuture;
    if (_requests.isCurrent(request)) {
      _syncDanmaku(player.playing);
    }
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

  Future<void> _loadDanmaku(int index, int request) async {
    List<DanmakuModel> list;
    try {
      list = await _fetchDanmaku(typeId, hid, index);
      if (!_requests.isCurrent(request)) {
        return;
      }
      list = List<DanmakuModel>.of(list)
        ..sort((a, b) => a.time.compareTo(b.time));
      Log.i('分P ${index + 1} 加载弹幕 ${list.length} 条');
    } catch (e, stackTrace) {
      if (!_requests.isCurrent(request)) {
        return;
      }
      Log.e('弹幕加载失败', error: e, stackTrace: stackTrace);
      list = const [];
    }
    // 分P相同也可能来自不同请求, 必须检查代次, 关闭后也丢弃.
    if (!_requests.isCurrent(request)) {
      return;
    }
    _danmaku = list;
    // 弹幕到位后重新定位, 避免把已经播过的弹幕一次性丢进渲染器.
    _lastPosition = -1;
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

  /// 弹幕渲染配置, 可预览正在编辑的样式.
  DanmakuOption get danmakuOption =>
      (_danmakuPreferences ?? DanmakuPreferencesStore.read()).toOption();

  /// 面板预览或偏好变更都使用同一入口, 不因改样式恢复暂停播放.
  void applyDanmakuPreferences(DanmakuPreferences preferences) {
    if (_closed) return;
    _danmakuPreferences = preferences.normalized;
    danmakuEnabled.value = _danmakuPreferences!.enabled;
    final controller = _danmakuController;
    if (controller == null) return;
    controller.updateOption(danmakuOption);
    if (!danmakuEnabled.value) {
      controller.clear();
      controller.pause();
    } else if (player.playing) {
      controller.resume();
    } else {
      controller.pause();
    }
  }

  Future<void> toggleDanmaku() async {
    final next = DanmakuPreferencesStore.read().copyWith(
      enabled: !danmakuEnabled.value,
    );
    try {
      await DanmakuPreferencesStore.save(next);
      applyDanmakuPreferences(next);
    } catch (error, stackTrace) {
      Log.e('保存弹幕开关失败', error: error, stackTrace: stackTrace);
    }
  }

  Future<void> togglePlay() async {
    if (player.completed) {
      // 从头重播, 弹幕游标归零但保留已拉取的弹幕.
      await player.seek(Duration.zero);
      await player.play();
      _rewindDanmaku();
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

  /// 设置音量, 0-100.
  Future<void> setVolume(double volume) async {
    await player.setVolume(volume);
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
    final request = _requests.current;
    final time = player.position.inMilliseconds / 1000;
    sending.value = true;
    try {
      final raw = await DanmakuHttp.send(
        typeId: typeId,
        hid: hid,
        part: part.value,
        text: content,
        time: time,
      );
      final result = _parseSendResult(raw);
      if (result != null || !_requests.isCurrent(request)) {
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
      if (!_closed) {
        sending.value = false;
      }
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
    final currentPart = _playingPart;
    if (current == null || currentPart == null) {
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
        part: currentPart,
        progress: progress,
        duration: total,
      );
    } catch (e, stackTrace) {
      Log.e('写入播放历史失败', error: e, stackTrace: stackTrace);
    }
  }

  void _onPlayerChanged() {
    final playing = player.playing;
    final paused = _wasPlaying && !playing;
    _wasPlaying = playing;
    if (paused) {
      // 暂停时补记一次, 避免定时器还没走到就退出的情况.
      unawaited(recordHistory());
    }
    _syncDanmaku(playing);
  }

  /// 按播放位置投递弹幕, 而不是一次性全部交给渲染器.
  void _syncDanmaku(bool playing) {
    if (_closed || !playerReady.value) {
      return;
    }
    final controller = _danmakuController;
    if (controller == null) {
      return;
    }
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
    if (_lastPosition < 0) {
      // 刚加载完弹幕或刚开始播放, 跳过已经播过的部分.
      _nextDanmaku = _lowerBound(current);
    } else if ((current - _lastPosition).abs() > _seekTolerance) {
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
    _rewindDanmaku();
  }

  /// 弹幕游标归零, 保留已拉取的列表.
  void _rewindDanmaku() {
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
