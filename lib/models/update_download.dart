import 'package:tucao/models/release_asset.dart';

/// 更新包下载的阶段.
enum UpdateDownloadStatus {
  /// 还没有任务.
  idle,

  /// 正在下载.
  downloading,

  /// 被中断, 只能重新开始, 不做断点续传.
  paused,

  /// 安装包已就绪, 可以交给系统安装器.
  ready,

  /// 失败, 原因见 [UpdateDownloadState.error].
  failed,
}

/// 更新包下载的当前状态.
///
/// 界面订阅的是这一份不可变快照, 服务每次替换整个对象,
/// 界面因此不会读到半更新的阶段与进度.
class UpdateDownloadState {
  const UpdateDownloadState({
    this.status = UpdateDownloadStatus.idle,
    this.version = '',
    this.asset,
    this.received = 0,
    this.total = -1,
    this.path = '',
    this.error,
  });

  /// 没有任务时的初始状态.
  static const idle = UpdateDownloadState();

  final UpdateDownloadStatus status;

  /// 对应的发布标签, 用来判断提示的是不是同一个版本.
  final String version;

  /// 正在下载或已经下载好的产物, 没有匹配的安装包时为空.
  final ReleaseAsset? asset;

  final int received;
  final int total;

  /// 安装包就绪后的完整路径.
  final String path;

  final String? error;

  /// 是否有一个需要界面展示的任务, 下载中与已就绪都算.
  bool get hasTask => status != UpdateDownloadStatus.idle;

  bool get isDownloading => status == UpdateDownloadStatus.downloading;

  /// 已接收字节的比例, 总长度未知时为 null, 界面改用不确定进度条.
  double? get progress =>
      total > 0 ? (received / total).clamp(0.0, 1.0) : null;

  /// 安装包的体积, 接口没有给出时为 -1.
  int get expectedSize => asset?.size ?? -1;

  UpdateDownloadState update({
    UpdateDownloadStatus? status,
    String? version,
    ReleaseAsset? asset,
    int? received,
    int? total,
    String? path,
    String? error,
  }) => UpdateDownloadState(
    status: status ?? this.status,
    version: version ?? this.version,
    asset: asset ?? this.asset,
    received: received ?? this.received,
    total: total ?? this.total,
    path: path ?? this.path,
    error: error,
  );
}
