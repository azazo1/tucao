import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:tucao/common/constants.dart';
import 'package:tucao/http/api_path.dart';
import 'package:tucao/models/video.dart';
import 'package:tucao/utils/http_util.dart';

/// 官网单向新增收藏接口, 不与本地收藏按钮混用.
/// 依据官网播放页 add_favorite, 未证实个人列表/删除接口, 不提供猜测实现.
abstract final class FavoriteHttp {
  static Future<void> add({
    required VideoModel video,
    CancelToken? cancelToken,
  }) async {
    if (!RegExp(r'^[0-9]+$').hasMatch(video.hid) ||
        video.typeId <= 0 ||
        video.title.trim().isEmpty) {
      throw ArgumentError('收藏需要有效的视频 id, 分区和标题');
    }
    final response = await HttpUtil.dio.get(
      '${Constants.baseUrl}api.php',
      queryParameters: {
        'op': 'add_favorite',
        'title': video.title,
        'url': '/play/h${video.hid}/',
        'contentid': video.hid,
        // 官网视频内容模型固定为 11, ccatid 才是视频分区.
        'modelid': ApiPath.videoModelId,
        'ccatid': video.typeId,
        'cusername': video.userName,
        'cdescription': video.description,
        'ccatname': video.typeName,
        'cuserid': video.userId,
        'thumb': video.cover,
      },
      options: Options(
        validateStatus: (status) =>
            status != null && status >= 200 && status < 300,
      ),
      cancelToken: cancelToken,
    );
    if (!isSuccess(response.data?.toString() ?? '')) {
      throw StateError('站点未确认收藏成功, 请检查登录状态后重试');
    }
  }

  /// 仅官网脚本检查的 status=1 表示成功, 空正文和提示 HTML 都不算.
  static bool isSuccess(String raw) {
    var text = raw.replaceFirst('\ufeff', '').trim();
    if (text.startsWith('(') && text.endsWith(')')) {
      text = text.substring(1, text.length - 1);
    }
    try {
      final value = jsonDecode(text);
      return value is Map && (value['status'] == 1 || value['status'] == '1');
    } on FormatException {
      return false;
    }
  }
}
