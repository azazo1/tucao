import 'package:dio/dio.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:tucao/common/constants.dart';
import 'package:tucao/http/api_path.dart';
import 'package:tucao/models/video.dart';
import 'package:tucao/utils/http_util.dart';
import 'package:tucao/utils/logger.dart';

/// 番组索引数据源.
///
/// 站点只提供 html, 没有 json 接口, 与排行榜一样按 UA 返回不同内容,
/// 必须用桌面 UA 请求. 桌面模板的条目在 `div.list > div.item`,
/// 移动模板在 `div.loop_content > div.item`, 两套模板字段含义一致,
/// 这里统一解析.
abstract final class BgmHttp {
  /// 站点每页固定返回的条数, 用于判断是否还有下一页.
  static const pageSize = 50;

  /// 季度筛选项, 与站点上的 "季度" 一栏一致.
  static const seasonOptions = <String, int>{
    '1月': 1,
    '4月': 4,
    '7月': 7,
    '10月': 10,
    '剧场版': 99,
  };

  /// 年代筛选项, 与站点上的 "年代" 一栏一致.
  static const yearOptions = <String>[
    '1906-1999',
    '2000-2009',
    '2010',
    '2011',
    '2012',
    '2013',
    '2014',
    '2015',
    '2016',
    '2017',
    '2018',
    '2019',
    '2020',
    '2021',
    '2022',
    '2023',
    '2024',
    '2025',
    '2026',
    '2027',
  ];

  /// 拉取一页番组.
  ///
  /// [month] 为 1-12 的月份, [year] 为四位年份或站点给出的年代区间,
  /// [types] 为题材关键词, 例如 恋爱. 均为空表示不限.
  static Future<List<VideoModel>> fetch({
    int? month,
    String? year,
    String? types,
    int page = 1,
    CancelToken? cancelToken,
  }) async {
    final response = await HttpUtil.dio.get(
      '${Constants.baseUrl}${ApiPath.bgmUrl}',
      queryParameters: {
        'page': page,
        'month': ?month,
        'year': ?year,
        'types': ?types,
      },
      cancelToken: cancelToken,
      options: Options(headers: {'user-agent': Constants.desktopUserAgent}),
    );
    final raw = response.data.toString();
    final list = parseBgmHtml(raw);
    Log.i(
      '番组索引 month=${month ?? '全部'} year=${year ?? '全部'} '
      'types=${types ?? '全部'} 第 $page 页: '
      '解析到 ${list.length} 条, 共 ${_parseTotal(raw)} 条',
    );
    return list;
  }

  /// 解析番组页面.
  ///
  /// 每个条目里的地址, 封面, 标题与播放数直接对应 [VideoModel] 的字段,
  /// 集数状态与题材标签没有对应字段, 分别放进 description 与 keywords.
  static List<VideoModel> parseBgmHtml(String raw) {
    final document = html_parser.parse(raw);
    final list = <VideoModel>[];
    final seen = <String>{};
    for (final node in document.querySelectorAll(
      '.loop_content .item, .list .item',
    )) {
      final hid = _parseHid(node);
      if (hid == null || !seen.add(hid)) {
        continue;
      }
      list.add(
        VideoModel(
          hid: hid,
          title: node.querySelector('.t')?.text.trim() ?? '',
          cover: _parseCover(node),
          playCount: _parseCount(node.querySelector('.i')?.text ?? ''),
          description: _parseState(node),
          keywords: node.querySelector('b')?.text.trim() ?? '',
          url: '/play/h$hid/',
        ),
      );
    }
    return list;
  }

  /// 条目里第一个指向播放页的地址, 移动模板在包裹的 a 上,
  /// 桌面模板在 `a.p` 上, 都取播放页的 hid.
  static String? _parseHid(dom.Element node) {
    for (final link in node.querySelectorAll('a')) {
      final match = RegExp(
        r'/play/h?(\d+)/',
      ).firstMatch(link.attributes['href'] ?? '');
      if (match != null) {
        return match.group(1);
      }
    }
    return null;
  }

  /// 封面在 img 的 style 里, src 只是占位图, 解析不到时再退回 src.
  static String _parseCover(dom.Element node) {
    final image = node.querySelector('img');
    final style =
        image?.attributes['style'] ??
        node.querySelector('a')?.attributes['style'] ??
        '';
    final cover = _parseBackground(style);
    return cover.isNotEmpty ? cover : image?.attributes['src'] ?? '';
  }

  /// 集数状态, 桌面模板是 `.c span`, 移动模板是 `.b span`.
  static String _parseState(dom.Element node) {
    final text =
        node.querySelector('.c span')?.text ??
        node.querySelector('.b span')?.text ??
        '';
    return text.trim();
  }

  static String _parseBackground(String style) {
    final match = RegExp(r'url\(([^)]+)\)').firstMatch(style);
    return match?.group(1)?.replaceAll(RegExp(r'''^["']|["']$'''), '') ?? '';
  }

  /// 播放数带千分位逗号.
  static int _parseCount(String text) {
    final match = RegExp(r'([\d,]+)').firstMatch(text);
    if (match == null) {
      return 0;
    }
    return int.tryParse(match.group(1)!.replaceAll(',', '')) ?? 0;
  }

  /// 页面标注的总条数, 形如 `共525条 / 第1页`, 只用于日志.
  static int _parseTotal(String raw) {
    final match = RegExp(r'共(\d+)条').firstMatch(raw);
    return match == null ? 0 : int.tryParse(match.group(1)!) ?? 0;
  }
}
