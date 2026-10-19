import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as path;
import 'package:tucao/models/release_asset.dart';
import 'package:tucao/models/update_download.dart';
import 'package:tucao/services/update/update_installer.dart';
import 'package:tucao/services/update/update_location.dart';
import 'package:tucao/services/update/update_transport.dart';
import 'package:tucao/utils/logger.dart';

/// 安装包的安装结果, 界面据此给出不同提示.
enum UpdateInstallOutcome {
  /// 已经交给系统安装器.
  started,

  /// 需要先在系统设置里允许本应用安装未知应用.
  permissionRequired,

  /// 安装包不在本地, 需要重新下载.
  missing,

  /// 其他失败, 例如系统里没有能处理安装意图的应用.
  failed,
}

/// 更新包的前台下载.
///
/// 更新包只有一份且体积有限, 因此不做队列与断点续传: 同时只允许一个任务,
/// 中断后从头再来, 半成品随任务一起丢弃. 下载全程要求应用在前台, 回到后台
/// 就中断, 所以不需要前台服务与常驻通知, 也不申请额外的后台权限.
class UpdateDownloadService extends GetxController
    with WidgetsBindingObserver {
  UpdateDownloadService({
    required UpdateTransport transport,
    Future<Directory> Function()? location,
  }) : _transport = transport,
       _location = location ?? UpdateLocation.directory;

  static UpdateDownloadService get instance =>
      Get.find<UpdateDownloadService>();

  /// 没有注册时返回 null, 供不涉及更新的界面与测试使用.
  static UpdateDownloadService? get maybeInstance =>
      Get.isRegistered<UpdateDownloadService>()
      ? Get.find<UpdateDownloadService>()
      : null;

  final UpdateTransport _transport;
  final Future<Directory> Function() _location;

  /// 当前任务状态, 界面订阅它.
  final state = UpdateDownloadState.idle.obs;

  Directory? _directory;
  CancelToken? _cancel;
  Future<void>? _active;
  String? _version;
  List<ReleaseAsset> _assets = const [];
  List<String> _abis = const [];
  bool _foreground = true;
  bool _closed = false;

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    _closed = true;
    if (_cancel?.isCancelled == false) {
      _cancel?.cancel('更新下载已关闭');
    }
    super.onClose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_closed) {
      return;
    }
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _foreground = false;
      unawaited(
        pause().catchError((Object error, StackTrace stackTrace) {
          Log.e('中断更新包下载失败', error: error, stackTrace: stackTrace);
        }),
      );
    } else if (state == AppLifecycleState.resumed) {
      _foreground = true;
    }
  }

  /// 开始下载匹配设备 ABI 的安装包.
  ///
  /// [version] 用于判断任务针对的是不是同一个版本, [assets] 是这一次发布或
  /// 分支构建提供的产物. 同一个版本正在下载时不重复发起, 已经下好同一个包
  /// 时直接沿用.
  Future<void> start({
    required String version,
    required List<ReleaseAsset> assets,
    required List<String> abis,
  }) async {
    if (_closed) {
      return;
    }
    _version = version;
    _assets = assets;
    _abis = abis;
    final asset = ReleaseAsset.pickFor(assets, abis);
    if (asset == null) {
      state.value = UpdateDownloadState(
        status: UpdateDownloadStatus.failed,
        version: version,
        error: '这个版本没有适配当前设备的安装包, 请在发布页里选择',
      );
      return;
    }
    final current = state.value;
    if (current.version == version) {
      if (current.isDownloading) {
        return;
      }
      if (current.status == UpdateDownloadStatus.ready &&
          current.asset?.name == asset.name) {
        return;
      }
    }
    // 上一个任务无论是下载中还是失败, 都要先收尾再开新的.
    await pause();
    if (_closed) {
      return;
    }
    if (!_foreground) {
      state.value = UpdateDownloadState(
        status: UpdateDownloadStatus.paused,
        version: version,
        asset: asset,
        error: '应用不在前台, 回到应用后再开始下载',
      );
      return;
    }
    // 先登记取消令牌再开始下载: 下载途中回到后台或用户取消都靠它.
    final token = CancelToken();
    _cancel = token;
    final running = _download(asset, version, token);
    _active = running;
    try {
      await running;
    } finally {
      if (identical(_active, running)) {
        _active = null;
      }
    }
  }

  /// 重新开始上一次的下载, 用于中断或失败之后的重试.
  Future<void> retry() async {
    final version = _version;
    if (version == null) {
      return;
    }
    await start(version: version, assets: _assets, abis: _abis);
  }

  /// 中断当前下载. 已经下好的安装包不受影响, 半成品由收尾流程丢弃.
  Future<void> pause() async {
    final token = _cancel;
    final running = _active;
    if (token == null) {
      if (running != null) {
        await running;
      }
      return;
    }
    if (!token.isCancelled) {
      if (state.value.isDownloading) {
        state.value = state.value.update(
          status: UpdateDownloadStatus.paused,
          received: 0,
          total: -1,
        );
      }
      token.cancel('更新下载已暂停');
    }
    if (running != null) {
      await running;
    }
  }

  /// 放弃当前任务, 连同半成品与已下好的安装包一起删掉.
  Future<void> discard() async {
    await pause();
    await _deletePackageFiles();
    state.value = UpdateDownloadState.idle;
  }

  /// 用系统安装器打开已经下好的安装包.
  Future<UpdateInstallOutcome> install() async {
    final current = state.value;
    if (current.status != UpdateDownloadStatus.ready ||
        current.path.isEmpty) {
      return UpdateInstallOutcome.missing;
    }
    var exists = false;
    try {
      exists = await File(current.path).exists();
    } on FileSystemException catch (error) {
      Log.w('检查安装包失败: $error');
    }
    if (!exists) {
      state.value = current.update(
        status: UpdateDownloadStatus.failed,
        error: '安装包已不在本地, 请重新下载',
      );
      return UpdateInstallOutcome.missing;
    }
    if (!await UpdateInstaller.canInstall()) {
      return UpdateInstallOutcome.permissionRequired;
    }
    if (!await UpdateInstaller.install(current.path)) {
      return UpdateInstallOutcome.failed;
    }
    Log.i('已交给系统安装器 ${path.basename(current.path)}');
    return UpdateInstallOutcome.started;
  }

  Future<void> _download(
    ReleaseAsset asset,
    String version,
    CancelToken token,
  ) async {
    Directory directory;
    try {
      directory = await _ensureDirectory();
    } catch (error, stackTrace) {
      Log.e('更新包目录不可用', error: error, stackTrace: stackTrace);
      state.value = UpdateDownloadState(
        status: UpdateDownloadStatus.failed,
        version: version,
        asset: asset,
        error: '无法创建更新包目录, 请检查存储空间',
      );
      return;
    }
    final target = File(path.join(directory.path, asset.name));
    final temporary = File('${target.path}.part');
    // 目录里只保留本次要用的包, 旧版本与上次的半成品都没有别的用途.
    await _deletePackageFiles(keep: asset.name);
    final watch = Stopwatch()..start();
    var lastUpdate = -250;
    state.value = UpdateDownloadState(
      status: UpdateDownloadStatus.downloading,
      version: version,
      asset: asset,
      total: asset.size > 0 ? asset.size : -1,
    );
    try {
      Log.i('开始下载更新包 ${asset.name}');
      final bytes = await _transport.fetch(
        uri: Uri.parse(asset.downloadUrl),
        target: temporary,
        cancelToken: token,
        onProgress: (received, total) {
          if (watch.elapsedMilliseconds - lastUpdate < 250) {
            return;
          }
          lastUpdate = watch.elapsedMilliseconds;
          final current = state.value;
          if (token.isCancelled ||
              !identical(_cancel, token) ||
              !current.isDownloading) {
            return;
          }
          state.value = current.update(
            received: received,
            total: total > 0 ? total : current.total,
          );
        },
      );
      // 暂停或已被新任务取代时, 状态由那一侧负责, 这里只负责收尾.
      if (token.isCancelled || !identical(_cancel, token)) {
        return;
      }
      if (asset.size > 0 && bytes != asset.size) {
        throw FormatException(
          '安装包与发布记录的大小不一致, 预期 ${asset.size} 字节, 实际 $bytes 字节',
        );
      }
      if (await target.exists()) {
        await target.delete();
      }
      await temporary.rename(target.path);
      state.value = UpdateDownloadState(
        status: UpdateDownloadStatus.ready,
        version: version,
        asset: asset,
        received: bytes,
        total: bytes,
        path: target.path,
      );
      Log.i(
        '更新包已就绪 ${asset.name}, $bytes 字节, 耗时 ${watch.elapsedMilliseconds}ms',
      );
    } catch (error, stackTrace) {
      final cancelled = token.isCancelled;
      if (!cancelled) {
        Log.e('下载更新包失败', error: error, stackTrace: stackTrace);
      }
      if (identical(_cancel, token)) {
        state.value = state.value.update(
          status: cancelled
              ? UpdateDownloadStatus.paused
              : UpdateDownloadStatus.failed,
          received: 0,
          total: -1,
          error: cancelled ? null : _errorText(error),
        );
      }
    } finally {
      if (identical(_cancel, token)) {
        _cancel = null;
      }
      await _deleteFile(temporary);
    }
  }

  Future<Directory> _ensureDirectory() async {
    final cached = _directory;
    if (cached != null) {
      return cached;
    }
    final directory = await _location();
    await directory.create(recursive: true);
    return _directory = directory;
  }

  /// 删掉目录里的安装包与半成品, [keep] 指定的文件名除外.
  Future<void> _deletePackageFiles({String keep = ''}) async {
    final directory = _directory;
    if (directory == null) {
      return;
    }
    List<FileSystemEntity> entries;
    try {
      entries = await directory.list().toList();
    } on FileSystemException catch (error) {
      Log.w('读取更新包目录失败: $error');
      return;
    }
    for (final entry in entries) {
      if (entry is! File) {
        continue;
      }
      final name = path.basename(entry.path);
      if (name == keep || !_isPackage(name)) {
        continue;
      }
      await _deleteFile(entry);
    }
  }

  static bool _isPackage(String name) {
    final lower = name.toLowerCase();
    return lower.endsWith('.apk') || lower.endsWith('.part');
  }

  static Future<void> _deleteFile(File file) async {
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } on FileSystemException catch (error) {
      Log.w('删除 ${path.basename(file.path)} 失败: $error');
    }
  }

  static String _errorText(Object error) {
    if (error is FormatException) {
      return error.message;
    }
    if (error is FileSystemException) {
      return '无法写入安装包, 请检查剩余空间';
    }
    return '下载失败, 请检查网络后重试';
  }
}
