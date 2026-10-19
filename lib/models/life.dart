/// 站点的续命数据.
class LifeStatus {
  const LifeStatus({
    required this.survivalDays,
    required this.myDays,
    this.contributors = const [],
    this.member = const MemberStats(),
  });

  /// cc娘还能存活的天数, 站点给的是带小数的天.
  final double survivalDays;

  /// 我已为ta续命的天数.
  final double myDays;

  /// 贡献者头像, 站点只给前几位, 按贡献从高到低.
  final List<String> contributors;

  /// 同一页面上的会员数值.
  final MemberStats member;
}

/// 会员中心用户栏上的数值.
class MemberStats {
  const MemberStats({
    this.groupName = '',
    this.credit = 0,
    this.guardDays = 0,
    this.residentYears = 0,
  });

  /// 会员组名, 站点用 `1元0次` 到 `1元9次` 的趣味命名.
  final String groupName;

  /// 积分, 评论, 每日登录, 投稿, 在线与点击广告都会增加.
  final int credit;

  /// 守护天数, 与 [LifeStatus.myDays] 是同一个数.
  final double guardDays;

  /// 居住年数, 也就是账号年限.
  final int residentYears;
}

/// 贡献榜的一个条目.
///
/// TOFIX(site): 贡献榜条目缺用户 id, 点击后无法进对应用户空间.
///
/// 站点现在的条目只有头像与昵称文本:
///
/// ```html
/// <div class="item">
///   <span class="n1">1</span>
///   <img src="/phpsso_server/uploadfile/avatar/9/3/82772/180x180.jpg">
///   <div class="i"><div class="l" style="width:1.52%;"></div></div>
///   <div class="a">Yuu夕，续命5.49天</div>
/// </div>
/// ```
///
/// 头像路径里的 82772 是 phpsso 的 uid, 与用户空间的 id 不是一套编号
/// (`/play/u82772/` 是另一位用户, Yuu夕 实际是 `/play/u82749/`), 所以
/// 没法从现有页面反推.
///
/// 需要站点补的接口, 下面任一种都够用, 结构不必大改:
/// - 把昵称包进链接: `<a href="/play/u82749/">Yuu夕</a>`
/// - 或在条目上加属性: `<div class="item" data-uid="82749">`
/// - 或提供 json: `index.php?m=member&c=life_rank&format=json`,
///   每条带上 uid 与昵称.
///
/// 站点补上之后, 在 [LifeHttp.parseRankHtml] 里解析出 uid 并给条目加
/// 点击即可, 界面不用动.
class LifeRankItem {
  const LifeRankItem({
    required this.rank,
    required this.userName,
    required this.days,
    this.avatar = '',
    this.ratio = 0,
  });

  /// 名次, 取自条目上的序号.
  final int rank;

  final String userName;

  /// 该用户为站点续命的天数.
  final double days;

  final String avatar;

  /// 站点在条目上给出的百分比, 站点自己是按这个排的序.
  final double ratio;
}

/// 贡献榜.
class LifeRank {
  const LifeRank({
    required this.items,
    this.sourceArticleId = '',
    this.requiresLogin = false,
  });

  final List<LifeRankItem> items;

  /// 页脚 "数据来源AD" 指向的公告 id, 形如 `7130`, 取不到时为空.
  final String sourceArticleId;

  /// 未登录时站点只回会话过期的提示页, 此时为 true.
  final bool requiresLogin;
}

/// 取不到续命数据时的粗诊断.
///
/// 站点对未登录请求只回一页会话过期的提示, 与"模板改了"表现相同,
/// 都拿不到续命区块. 这里把能区分两者的几个特征带出来, 便于在界面上
/// 一眼看出该让用户重新登录, 还是该修解析.
class LifeDiagnosis {
  const LifeDiagnosis({
    required this.length,
    required this.expired,
    required this.hasLifeBlock,
    required this.hasMemberNav,
  });

  /// 返回的 HTML 长度, 站点正常页面在数十万字节量级.
  final int length;

  /// 页面里是否出现会话过期的提示.
  final bool expired;

  /// 是否有续命区块本身.
  final bool hasLifeBlock;

  /// 是否有指向贡献榜的链接, 用于判断会员中心是否渲染出来.
  final bool hasMemberNav;

  /// 给人看的结论.
  String describe() {
    if (expired) {
      return '站点返回会话过期提示, 需要重新登录';
    }
    if (length == 0) {
      return '站点返回了空页面';
    }
    if (hasMemberNav) {
      return '会员中心已渲染但没有续命区块, 可能是站点改版';
    }
    return '页面 $length 字节, 但不像会员中心, 可能被重定向';
  }
}

/// 续命天数的文案, 整数不带小数点, 小数最多两位.
///
/// 站点的文案形如 `7.85天` 与 `0天`, 解析回来是 double, 这里按同样的
/// 习惯还原, 免得界面上出现 `0.00天`.
String formatLifeDays(double days) {
  if (!days.isFinite) {
    return '0';
  }
  if (days == days.roundToDouble()) {
    return days.toStringAsFixed(0);
  }
  return days.toStringAsFixed(2).replaceFirst(RegExp(r'0$'), '');
}
