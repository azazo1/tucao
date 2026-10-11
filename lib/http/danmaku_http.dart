import 'package:dio/dio.dart';
import 'package:tucao/common/constants.dart';
import 'package:tucao/http/api_path.dart';
import 'package:tucao/models/danmaku.dart';
import 'package:tucao/utils/http_util.dart';
import 'package:xml/xml.dart';

/// 弹幕接口.
abstract final class DanmakuHttp {
  /// 拉取某一分P的弹幕.
  ///
  /// 接口返回 xml, 结构为 `<i><d p="时间,类型,字号,颜色,时间戳,...">文本</d></i>`.
  static Future<List<DanmakuModel>> fetch({
    required String hid,
    required int part,
    CancelToken? cancelToken,
  }) async {
    final response = await HttpUtil.dio.get(
      '${Constants.baseUrl}${ApiPath.danmakuInit}',
      queryParameters: {
        'playerID': ApiPath.playerId(hid, part),
        'r': DateTime.now().millisecondsSinceEpoch,
      },
      cancelToken: cancelToken,
    );
    final raw = response.data.toString();
    if (raw.trim().isEmpty) {
      return const [];
    }
    final document = XmlDocument.parse(raw);
    final list = <DanmakuModel>[];
    for (final node in document.findAllElements('d')) {
      final text = node.innerText.trim();
      if (text.isEmpty) {
        continue;
      }
      final attr = node.getAttribute('p');
      if (attr == null) {
        continue;
      }
      list.add(DanmakuModel.fromAttr(attr, text));
    }
    return list;
  }

  /// 发送弹幕.
  ///
  /// 站点要求登录态, 未登录时会返回错误提示文本.
  static Future<String> send({
    required String hid,
    required int part,
    required String text,
    required double time,
    int color = 0xFFFFFF,
    int mode = 1,
    int fontSize = 25,
    CancelToken? cancelToken,
  }) async {
    final response = await HttpUtil.dio.post(
      '${Constants.baseUrl}${ApiPath.danmakuSend}',
      data: {
        'playerID': ApiPath.playerId(hid, part),
        'mukio': text,
        'color': '#${color.toRadixString(16).padLeft(6, '0')}',
        'size': fontSize,
        'type': mode,
        'time': time.toStringAsFixed(1),
      },
      options: Options(contentType: Headers.formUrlEncodedContentType),
      cancelToken: cancelToken,
    );
    return response.data.toString();
  }
}
