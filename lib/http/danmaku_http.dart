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
  /// 表单字段与官方客户端一致, 见官方 apk 的 RawApiService.sendDanmu:
  /// playerID 为查询参数, cid / stime / message / user / size / mode / color 为表单字段.
  /// 接口要求登录态, 未登录时返回错误提示.
  static Future<String> send({
    required String hid,
    required int part,
    required String text,
    required double time,
    int color = 0xFFFFFF,
    int mode = 1,
    int fontSize = 25,
    String user = '',
    CancelToken? cancelToken,
  }) async {
    final response = await HttpUtil.dio.post(
      '${Constants.baseUrl}${ApiPath.danmakuSend}',
      queryParameters: {'playerID': ApiPath.playerId(hid, part)},
      data: {
        'cid': hid,
        'stime': time.toStringAsFixed(1),
        'message': text,
        'user': user,
        'size': fontSize,
        'mode': mode,
        // 官方按十进制整数提交颜色.
        'color': color,
      },
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        headers: {'cookie': 'tucao_verify=ok'},
      ),
      cancelToken: cancelToken,
    );
    return response.data.toString();
  }
}
