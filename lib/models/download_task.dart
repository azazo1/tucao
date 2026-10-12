enum DownloadStatus { queued, downloading, paused, completed, failed }

/// 一条分P缓存任务. 文件名只由站内编号生成, 不使用标题或远端路径.
class DownloadTask {
  const DownloadTask({
    required this.hid,
    required this.part,
    required this.title,
    required this.partTitle,
    required this.source,
    required this.createdAt,
    this.status = DownloadStatus.queued,
    this.received = 0,
    this.total = -1,
    this.error,
  });

  final String hid;
  final int part;
  final String title;
  final String partTitle;
  final String source;
  final int createdAt;
  final DownloadStatus status;
  final int received;
  final int total;
  final String? error;

  String get id => '$hid-$part';
  double? get progress => total > 0 ? (received / total).clamp(0.0, 1.0) : null;

  DownloadTask update({
    DownloadStatus? status,
    String? source,
    int? received,
    int? total,
    String? error,
  }) => DownloadTask(
    hid: hid,
    part: part,
    title: title,
    partTitle: partTitle,
    source: source ?? this.source,
    createdAt: createdAt,
    status: status ?? this.status,
    received: received ?? this.received,
    total: total ?? this.total,
    error: error,
  );

  Map<String, dynamic> toJson() => {
    'hid': hid,
    'part': part,
    'title': title,
    'partTitle': partTitle,
    'source': source,
    'createdAt': createdAt,
    'status': status.name,
    'received': received,
    'total': total,
    'error': error,
  };

  static bool validIdentity(String hid, int part) =>
      RegExp(r'^[0-9]+$').hasMatch(hid) &&
      hid.contains(RegExp(r'[1-9]')) &&
      part >= 0;

  static Uri? sourceUri(String source) {
    final uri = Uri.tryParse(source);
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      return null;
    }
    return uri;
  }

  factory DownloadTask.fromJson(Map<String, dynamic> json) {
    final hid = json['hid'] as String;
    final part = json['part'] as int;
    final source = json['source'] as String;
    final received = json['received'] as int;
    final total = json['total'] as int;
    if (!validIdentity(hid, part) ||
        sourceUri(source) == null ||
        received < 0 ||
        total < -1) {
      throw const FormatException('无效的缓存任务');
    }
    return DownloadTask(
      hid: hid,
      part: part,
      title: json['title'] as String,
      partTitle: json['partTitle'] as String,
      source: source,
      createdAt: json['createdAt'] as int,
      status: DownloadStatus.values.byName(json['status'] as String),
      received: received,
      total: total,
      error: json['error'] as String?,
    );
  }
}
