import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:tucao/common/constants.dart';
import 'package:tucao/http/api_path.dart';
import 'package:tucao/models/site_favorite.dart';
import 'package:tucao/models/video.dart';
import 'package:tucao/utils/http_util.dart';

/// 站点追番 (官网叫收藏) 接口.
///
/// 只有新增是 json 接口, 依据官网播放页的 add_favorite, 站点按 url 与账号去重.
/// 个人列表与取消站点都没给 json, 只能读会员中心的追番夹页面:
/// 页面里每条记录带自己的记录号, 取消就是访问带该记录号的同一个地址.
abstract final class FavoriteHttp {
  /// 连站点自己都不分页时的兜底上限, 防止页面里的页码把它带飞.
  static const _maxFolderPages = 10;

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

  /// 读取整份追番夹.
  ///
  /// 站点没有查询单条状态的接口, 是否已追番只能这样整份判断;
  /// 追番夹按页返回, 页数取页面上的分页链接, 拉不动时才停.
  static Future<List<SiteFavoriteItem>> fetchFolder({
    CancelToken? cancelToken,
  }) async {
    final first = await _fetchFolderPage(1, cancelToken);
    final document = _folderDocument(first);
    final items = _parseItems(document);
    final pages = _folderPageCount(document).clamp(1, _maxFolderPages);
    final seen = items.map((item) => item.recordId).toSet();
    for (var page = 2; page <= pages; page++) {
      final raw = await _fetchFolderPage(page, cancelToken);
      for (final item in _parseItems(_folderDocument(raw))) {
        if (seen.add(item.recordId)) {
          items.add(item);
        }
      }
    }
    return items;
  }

  /// 取消一条追番.
  ///
  /// 站点把取消做成页面上的链接, 成功时返回的是提示页而不是追番夹,
  /// 因此这里只判登录态, 是否真的取消由调用方重新拉取列表确认.
  static Future<void> remove({
    required int recordId,
    CancelToken? cancelToken,
  }) async {
    if (recordId <= 0) {
      throw ArgumentError('取消追番需要有效的记录号');
    }
    final response = await HttpUtil.dio.get(
      '${Constants.baseUrl}${ApiPath.favoriteRemove(recordId)}',
      cancelToken: cancelToken,
    );
    final raw = response.data?.toString() ?? '';
    if (_looksLikeLogin(raw)) {
      throw StateError('站点未确认取消追番, 请检查登录状态后重试');
    }
  }

  /// 解析追番夹页面.
  ///
  /// 条目结构是 `div.mfav .item`: `.l a` 内容地址与 `.l img` 封面,
  /// `.t a` 标题, `.c a` 分区, `.tt` 投稿人与日期, `.m a` 取消链接.
  /// 站点按 UA 换皮肤, 这些类名取自会员中心的追番夹模板, 对不上时按
  /// 页面结构变化报错, 而不是假装追番是空的.
  static List<SiteFavoriteItem> parseFolder(String raw) =>
      _parseItems(_folderDocument(raw));

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

  static Future<String> _fetchFolderPage(
    int page,
    CancelToken? cancelToken,
  ) async {
    final path = ApiPath.favoriteFolder;
    final response = await HttpUtil.dio.get(
      '${Constants.baseUrl}${page <= 1 ? path : '$path&page=$page'}',
      cancelToken: cancelToken,
    );
    return response.data?.toString() ?? '';
  }

  static Document _folderDocument(String raw) {
    final document = html_parser.parse(raw);
    if (document.querySelector('.mfav') == null) {
      // 没登录与模板变化是两回事, 分开报, 免得用户照着提示反复重登.
      throw StateError(
        _looksLikeLogin(raw)
            ? '站点追番需要登录, 登录后再试'
            : '站点追番页面结构已变化, 请更新应用',
      );
    }
    return document;
  }

  /// 未登录时站点返回一页要求重新登录的提示, 不是追番夹.
  static bool _looksLikeLogin(String raw) =>
      raw.contains('会话已过期') || raw.contains('请重新登录');

  static List<SiteFavoriteItem> _parseItems(Document document) {
    final items = <SiteFavoriteItem>[];
    for (final node in document.querySelectorAll('.mfav .item')) {
      final item = _parseItem(node);
      if (item != null) {
        items.add(item);
      }
    }
    return items;
  }

  static SiteFavoriteItem? _parseItem(Element node) {
    final recordId = _recordIdOf(
      node.querySelector('.m a')?.attributes['href'],
    );
    final url = node.querySelector('.l a')?.attributes['href'] ?? '';
    final title = node.querySelector('.t a')?.text.trim() ?? '';
    if (recordId == null || title.isEmpty) {
      return null;
    }
    // 投稿人与日期在同一个单元格里, 用间隔点分开.
    final meta = (node.querySelector('.tt')?.text ?? '').split('·');
    final author = node.querySelector('.tt a')?.text.trim() ?? '';
    return SiteFavoriteItem(
      recordId: recordId,
      hid: _hidOf(url),
      title: title,
      cover: node.querySelector('.l img')?.attributes['src'] ?? '',
      typeName: node.querySelector('.c a')?.text.trim() ?? '',
      userName: author.isNotEmpty ? author : meta.first.trim(),
      savedDate: meta.length > 1 ? meta.last.trim() : '',
      description: node.querySelector('.d')?.text.trim() ?? '',
    );
  }

  /// 内容地址里的视频编号, 站点里还有 `d` 开头的档案类内容, 那些不算视频.
  static String _hidOf(String url) =>
      RegExp(r'^/play/h([0-9]+)/?$').firstMatch(url)?.group(1) ?? '';

  /// 取消链接里的追番记录号.
  static int? _recordIdOf(String? href) {
    final match = RegExp(r'[?&]id=([0-9]+)').firstMatch(href ?? '');
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  static int _folderPageCount(Document document) {
    var count = 1;
    for (final link in document.querySelectorAll('.pages a')) {
      final match = RegExp(
        r'[?&]page=([0-9]+)',
      ).firstMatch(link.attributes['href'] ?? '');
      final page = match == null ? null : int.tryParse(match.group(1)!);
      if (page != null && page > count) {
        count = page;
      }
    }
    return count;
  }
}
