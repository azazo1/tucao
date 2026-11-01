import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:path/path.dart' as path;
import 'package:tucao/utils/logger.dart';

/// 一段字节区间, 两端都包含.
typedef SegmentRange = ({int start, int end});

/// 分段下载计划: 文件总长与各段区间.
class SegmentPlan {
  const SegmentPlan({required this.total, required this.ranges});

  static const version = 1;

  final int total;
  final List<SegmentRange> ranges;

  /// 第 [index] 段的字节数.
  int length(int index) => ranges[index].end - ranges[index].start + 1;
}

/// 分段下载的磁盘布局, 全部文件都挂在分片 `<id>.part` 旁边.
///
/// 各段写进 `<分片>.s<序号>`, 计划写进 `<分片>.plan`. 计划在, 续传就按各段已有长度
/// 接着下; 全部下完后按顺序拼进分片本身, 再删掉计划与各段.
abstract final class DownloadSegments {
  /// 每段至少 4 MiB, 太小的文件分段只会多出请求.
  static const minSize = 4 << 20;

  static File plan(File target) => File('${target.path}.plan');

  static File segment(File target, int index) => File('${target.path}.s$index');

  /// 把 [total] 切成至多 [connections] 段, 每段不小于 [minSize], 不足两段时为空.
  static List<SegmentRange>? split(
    int total,
    int connections, {
    int minSize = DownloadSegments.minSize,
  }) {
    final count = math.min(connections, total ~/ math.max(1, minSize));
    if (count < 2) {
      return null;
    }
    final size = (total / count).ceil();
    return [
      for (var index = 0; index < count; index++)
        (start: index * size, end: math.min(total, (index + 1) * size) - 1),
    ];
  }

  /// 读取计划, 没有或内容无效时为空; 无效的计划连同各段一起删掉.
  static Future<SegmentPlan?> load(File target) async {
    final file = plan(target);
    if (!await file.exists()) {
      return null;
    }
    try {
      final raw = jsonDecode(await file.readAsString());
      if (raw is Map &&
          raw['version'] == SegmentPlan.version &&
          raw['total'] is int &&
          raw['ranges'] is List) {
        final total = raw['total'] as int;
        final ranges = <SegmentRange>[];
        var next = 0;
        for (final entry in raw['ranges'] as List) {
          if (entry is! List || entry.length != 2) {
            throw const FormatException('分段区间格式错误');
          }
          final [start, end] = entry;
          if (start is! int || end is! int || start != next || end < start) {
            throw const FormatException('分段区间不连续');
          }
          ranges.add((start: start, end: end));
          next = end + 1;
        }
        if (total > 0 && ranges.length >= 2 && next == total) {
          return SegmentPlan(total: total, ranges: ranges);
        }
      }
      throw const FormatException('分段计划结构不受支持');
    } on FormatException catch (error) {
      Log.w('分段计划无效, 丢弃后重新下载: $error');
      await clear(target);
      return null;
    }
  }

  static Future<void> save(File target, SegmentPlan value) async {
    final file = plan(target);
    final temporary = File('${file.path}.new');
    await temporary.writeAsString(
      jsonEncode({
        'version': SegmentPlan.version,
        'total': value.total,
        'ranges': [
          for (final range in value.ranges) [range.start, range.end],
        ],
      }),
      flush: true,
    );
    await temporary.rename(file.path);
  }

  /// 按计划合计已下好的字节, 没有计划时为空.
  static Future<({int received, int total})?> progress(File target) async {
    final value = await load(target);
    if (value == null) {
      return null;
    }
    var received = 0;
    for (var index = 0; index < value.ranges.length; index++) {
      final file = segment(target, index);
      final have = await file.exists() ? await file.length() : 0;
      // 超长的段续传时会从头重下, 这里也不计入.
      if (have <= value.length(index)) {
        received += have;
      }
    }
    return (received: received, total: value.total);
  }

  /// 删掉计划与各段, 不碰分片本身.
  ///
  /// 先删计划: 中途失败最多留下无主的段文件, 不会让残缺的段被当成计划的一部分.
  /// 段文件按名字扫描, 计划已经丢失时也能清干净.
  static Future<void> clear(File target) async {
    final file = plan(target);
    for (final stale in [file, File('${file.path}.new')]) {
      if (await stale.exists()) {
        await stale.delete();
      }
    }
    final directory = Directory(path.dirname(target.path));
    if (!await directory.exists()) {
      return;
    }
    final pattern = RegExp('^${RegExp.escape(path.basename(target.path))}\\.s\\d+\$');
    await for (final entry in directory.list(followLinks: false)) {
      if (entry is File && pattern.hasMatch(path.basename(entry.path))) {
        await entry.delete();
      }
    }
  }
}
