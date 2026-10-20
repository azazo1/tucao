import 'package:dio/dio.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:tucao/common/constants.dart';
import 'package:tucao/http/api_path.dart';
import 'package:tucao/models/life.dart';
import 'package:tucao/utils/http_util.dart';
import 'package:tucao/utils/logger.dart';
import 'package:tucao/utils/site_url.dart';

/// 续命数据源.
///
/// 站点靠广告收益维持, 官方把这笔收益折算成 "cc娘还能存活多少天",
/// 用户自己那部分记在会员中心的 `.life` 区块里, 明细在贡献榜页面.
/// 两处都没有 json 接口, 因此抓页面解析; 页面需要登录态, 未登录时站点
/// 返回的是会话过期的提示页.
///
/// 站点以后若有变化, 处理方式如下:
/// - 若站点给出续命的 json 接口, 应当删掉这里的页面解析, 直接读字段.
/// - 若 `.life` 或 `.life_rank` 的类名改了, 只需调整本文件的解析.
/// - 若续命不再按天给出, 只需调整 [LifeStatus] 与调用方的文案.
abstract final class LifeHttp {
  /// 首页广告收益折算出的存活天数与会员数值.
  ///
  /// 会员中心是服务端渲染页面, 两种浏览器 UA 下模板可能不同, 因此按
  /// 手机 UA 优先, 解析不到续命区块时再用桌面 UA 试一次. 手机 UA 与登录
  /// 时的 UA 一致, 会话识别更稳妥.
  static Future<LifeStatus?> fetchStatus({CancelToken? cancelToken}) async {
    final attempts = <String>[
      Constants.userAgent,
      Constants.desktopUserAgent,
    ];
    String lastRaw = '';
    for (final userAgent in attempts) {
      final response = await HttpUtil.dio.get(
        '${Constants.baseUrl}${ApiPath.memberCenter}',
        options: Options(headers: {'user-agent': userAgent}),
        cancelToken: cancelToken,
      );
      final raw = response.data.toString();
      lastRaw = raw;
      final status = parseStatusHtml(raw);
      if (status != null) {
        return status;
      }
    }
    final diagnosis = diagnoseHtml(lastRaw);
    _lastDiagnosis = diagnosis;
    Log.i('两种 UA 都没解析到续命区块: ${diagnosis.describe()}');
    return null;
  }

  /// 最近一次 [fetchStatus] 没拿到数据时的诊断, 供界面显示.
  static LifeDiagnosis? _lastDiagnosis;

  static LifeDiagnosis? get lastDiagnosis => _lastDiagnosis;

  /// 对一页 HTML 做粗诊断, 用于判断是没登录还是模板变了.
  static LifeDiagnosis diagnoseHtml(String raw) {
    final text = raw.trim();
    return LifeDiagnosis(
      length: text.length,
      expired: text.contains('会话已过期') || text.contains('重新登录'),
      hasLifeBlock: text.contains('class="life"'),
      hasMemberNav: text.contains('m=member&amp;c=life_rank') ||
          text.contains('m=member&c=life_rank'),
    );
  }

  /// 贡献榜.
  static Future<LifeRank> fetchRank({CancelToken? cancelToken}) async {
    final response = await HttpUtil.dio.get(
      '${Constants.baseUrl}${ApiPath.lifeRank}',
      options: Options(headers: {'user-agent': Constants.userAgent}),
      cancelToken: cancelToken,
    );
    return parseRankHtml(response.data.toString());
  }

  /// 解析会员中心里的续命区块.
  ///
  /// 结构是 `div.mindex` 下的 `div.life`: `div.d` 是存活天数,
  /// `div.m` 是本人已续命的天数, `div.h` 里是贡献者的头像.
  /// 未登录时页面没有这个区块, 这里返回 null.
  static LifeStatus? parseStatusHtml(String raw) {
    if (raw.trim().isEmpty) {
      return null;
    }
    final document = html_parser.parse(raw);
    final life = document.querySelector('.life');
    if (life == null) {
      Log.i('会员中心没有续命区块, 按未登录处理');
      return null;
    }

    final contributors = <String>[];
    for (final image in life.querySelectorAll('.h img')) {
      final src = _absolute(image.attributes['src']?.trim() ?? '');
      if (src.isNotEmpty) {
        contributors.add(src);
      }
    }

    final status = LifeStatus(
      survivalDays: _parseNumber(life.querySelector('.d')?.text ?? ''),
      myDays: _parseNumber(life.querySelector('.m')?.text ?? ''),
      contributors: contributors,
      member: _parseMember(document),
    );
    Log.i(
      '续命区块解析完成, 还能存活 ${status.survivalDays} 天, '
      '本人 ${status.myDays} 天, 贡献者 ${contributors.length} 人',
    );
    return status;
  }

  /// 解析贡献榜页面.
  ///
  /// 条目是 `div.item`: 序号在 `span` 里, 头像在 `img` 里, 占比写在
  /// `div.i div.l` 的 style 上, 文案形如 `用户名，续命5.49天`.
  /// 页脚的 "数据来源AD" 指向说明用的公告, 这里一并取回来.
  ///
  /// 条目不带用户 id, 因此这里只能拿到昵称, 列表也就不可点.
  /// 缺什么见 [LifeRankItem] 上的 TOFIX(site).
  static LifeRank parseRankHtml(String raw) {
    if (raw.trim().isEmpty) {
      return const LifeRank(items: [], requiresLogin: true);
    }
    final document = html_parser.parse(raw);
    final sourceArticleId = _parseArticleId(
      document.querySelector('.life_link')?.attributes['href'] ?? '',
    );
    final container = document.querySelector('.life_rank');
    if (container == null || raw.contains('会话已过期')) {
      Log.i('贡献榜没有榜单区块, 按未登录处理');
      return LifeRank(
        items: const [],
        sourceArticleId: sourceArticleId,
        requiresLogin: true,
      );
    }

    final items = <LifeRankItem>[];
    var order = 0;
    for (final item in container.querySelectorAll('.item')) {
      final label = item.querySelector('.a')?.text.trim() ?? '';
      final userName = _parseUserName(label);
      if (userName.isEmpty) {
        continue;
      }
      order++;
      // 站点给前三名加 n1n2n3 类名, 序号都写在 span 里, 取不到时按顺序补.
      final rank = _parseNumber(item.querySelector('span')?.text ?? '').toInt();
      items.add(
        LifeRankItem(
          rank: rank > 0 ? rank : order,
          userName: userName,
          days: _parseDays(label),
          avatar: avatarUrl(
            item.querySelector('img')?.attributes['src'] ?? '',
          ),
          ratio: _parseRatio(item.querySelector('.i .l')),
        ),
      );
    }
    Log.i('贡献榜解析完成, 共 ${items.length} 条');
    return LifeRank(items: items, sourceArticleId: sourceArticleId);
  }

  /// 解析会员中心用户栏上的数值.
  ///
  /// 用户栏是 `a.name`, 里面依次是 `居住0年` `守护0天` `积分11` 这类
  /// 文字, 会员组名写在 `span` 里.
  static MemberStats _parseMember(Document document) {
    final name = document.querySelector('a.name');
    if (name == null) {
      return const MemberStats();
    }
    var credit = 0;
    var guardDays = 0.0;
    var residentYears = 0;
    for (final node in name.querySelectorAll('b')) {
      final text = node.text.trim();
      if (text.startsWith('积分')) {
        credit = _parseNumber(text).toInt();
      } else if (text.startsWith('守护')) {
        guardDays = _parseNumber(text);
      } else if (text.startsWith('居住')) {
        residentYears = _parseNumber(text).toInt();
      }
    }
    return MemberStats(
      groupName: name.querySelector('span')?.text.trim() ?? '',
      credit: credit,
      guardDays: guardDays,
      residentYears: residentYears,
    );
  }

  /// 条目文案里的用户名, 去掉结尾的 `，续命X天`.
  static String _parseUserName(String label) {
    return label
        .replaceAll(RegExp(r'[，,]?\s*续命\s*[\d.]+\s*天\s*$'), '')
        .trim();
  }

  /// 条目文案里的续命天数.
  static double _parseDays(String label) {
    final match = RegExp(r'续命\s*([\d.]+)\s*天').firstMatch(label);
    return double.tryParse(match?.group(1) ?? '') ?? 0;
  }

  /// 条目上的百分比, 站点按它排序, 数值比文案里的天数略旧, 只用于画长度.
  static double _parseRatio(Element? node) {
    final style = node?.attributes['style'] ?? '';
    final match = RegExp(r'width\s*:\s*([\d.]+)%').firstMatch(style);
    return double.tryParse(match?.group(1) ?? '') ?? 0;
  }

  /// 页面里第一个数字, 单位由调用方按文案决定.
  static double _parseNumber(String text) {
    final match = RegExp(r'\d+(?:\.\d+)?').firstMatch(text);
    return double.tryParse(match?.group(0) ?? '') ?? 0;
  }

  /// 页脚 "数据来源AD" 指向的公告 id.
  static String _parseArticleId(String href) {
    final match = RegExp(r'/play/[du]?(\d+)/').firstMatch(href);
    return match?.group(1) ?? '';
  }

  /// 头像与公告地址都是站内相对路径, 这里补成绝对地址.
  static String _absolute(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty || trimmed.startsWith('http')) {
      return trimmed;
    }
    return '${Constants.baseUrl}${trimmed.replaceFirst(RegExp(r'^/'), '')}';
  }
}
