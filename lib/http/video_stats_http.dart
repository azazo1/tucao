import 'package:dio/dio.dart';
import 'package:tucao/common/constants.dart';
import 'package:tucao/http/api_path.dart';
import 'package:tucao/utils/http_util.dart';

/// 播放页统计接口.
///
/// 站点这两个接口都返回一段 javascript, 用 `$('#id').html('value')`
/// 把数字写进页面, 这里直接把键值对解析出来.
abstract final class VideoStatsHttp {
  static final _htmlCall = RegExp(
    r"\$\('#([A-Za-z0-9_]+)'\)\.html\('([^']*)'\)",
  );

  /// 解析统计脚本里的赋值语句.
  static Map<String, String> parseScript(String raw) {
    final values = <String, String>{};
    for (final match in _htmlCall.allMatches(raw)) {
      values[match.group(1)!] = match.group(2)!;
    }
    return values;
  }

  /// 当前正在观看该视频的人数.
  ///
  /// 站点用 `hid` 拼接视频模型 id 作为 `cid`, 与播放页的调用一致.
  static Future<int?> fetchOnline({
    required String hid,
    CancelToken? cancelToken,
  }) async {
    if (hid.isEmpty) {
      return null;
    }
    final values = await _fetchScript(
      ApiPath.onlineScript,
      {
        'cid': '$hid${ApiPath.videoModelId}',
        // v=0 只返回数字, v=1 会返回一段自我轮询的脚本.
        'v': 0,
        't': DateTime.now().millisecondsSinceEpoch,
      },
      cancelToken,
    );
    return _intOf(values['olThis']);
  }

  /// 总播放量与追番数.
  static Future<({int? playCount, int? favoriteCount})> fetchCounts({
    required String hid,
    CancelToken? cancelToken,
  }) async {
    final values = await _fetchScript(
      ApiPath.videoCountScript,
      {'id': hid, 'modelid': ApiPath.videoModelId},
      cancelToken,
    );
    return (
      playCount: _intOf(values['hits']),
      favoriteCount: _intOf(values['fav']),
    );
  }

  static Future<Map<String, String>> _fetchScript(
    String path,
    Map<String, dynamic> query,
    CancelToken? cancelToken,
  ) async {
    final response = await HttpUtil.dio.get(
      '${Constants.baseUrl}$path',
      queryParameters: query,
      cancelToken: cancelToken,
    );
    return parseScript(response.data.toString());
  }

  static int? _intOf(String? raw) {
    if (raw == null) {
      return null;
    }
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    return digits.isEmpty ? null : int.tryParse(digits);
  }
}
