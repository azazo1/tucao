import 'package:tucao/common/constants.dart';

/// 站点接口地址定义.
///
/// 沿用官方安卓端的接口划分:
/// - json 接口位于 `api_v2/`, 返回结构化数据.
/// - xml 接口用于弹幕与评论.
/// - 部分数据官方也只提供 html, 需要抓页面解析, 见 [rankUrl] 等.
abstract final class ApiPath {
  /// json 接口.
  static const list = 'list.php';
  static const search = 'search.php';
  static const view = 'view.php';

  /// 播放页统计, 返回 javascript 而不是 json.
  static const onlineScript = 'ol.php';
  static const videoCountScript = 'api.php?op=count';

  /// 站点内容模型 id.
  ///
  /// 视频固定为 11, 档案资讯固定为 18; 与分区 id 不同.
  /// `api.php` 的 modelid 与 `ol.php` 的 cid 后缀都用它.
  static const videoModelId = 11;
  static const articleModelId = 18;

  /// 排行榜等页面数据在官方接口里已经废弃, 只能抓页面.
  static const rankHtml = 'html/hot.html';
  static const posHtml = 'html/pos.html';
  static const newHtml = 'html/new.html';
  static const weekBgmHtml = 'html/week_bgm.html';
  static const bgmUrl = 'bgm/';

  /// 弹幕.
  static const danmakuInit = 'index.php?m=mukio&c=index&a=init';
  static const danmakuSend = 'index.php?m=mukio&c=index&a=post';

  /// 评论.
  static const replyList = 'index.php?m=comment&c=index&a=ajax';

  /// 服务端渲染的评论页.
  ///
  /// 与 [replyList] 返回同一批一级评论, 区别是这里带会员昵称颜色,
  /// 用来标记破会员, 见 `VipHttp`.
  static const replyInit = 'index.php?m=comment&c=index&a=init';
  static const replySend = 'index.php?m=comment&c=index&a=post';
  static const replySupport =
      'index.php?m=comment&c=index&a=support&format=json';

  /// 图评图片上传, 只对破会员开放.
  ///
  /// commentid 是查询参数, 图片以 multipart 的 `file` 字段提交, 站点限制
  /// 单张 2MB. 上传成功后返回的片段插进评论正文, 再走 [replySend] 发送,
  /// 见 `ReplyHttp.uploadImage`.
  static const replyUploadImage = 'index.php?m=comment&c=index&a=upload_img';

  /// 用户.
  static const userInfo = 'api.php?op=user';
  static const userSpace = 'index.php?m=member&c=space';

  /// 会员中心与贡献榜.
  ///
  /// 站点没有对应的 json 接口, 都只能抓页面, 且需要登录态.
  static const memberCenter = 'index.php?m=member';
  static const lifeRank = 'index.php?m=member&c=life_rank';
  static const login = 'index.php?m=member&c=index&a=login';
  static const register = 'index.php?m=member&c=index&a=register&siteid=1';
  static const logout = 'index.php?m=member&c=index&a=logout&forward=&siteid=1';
  static const changePassword =
      'index.php?m=member&c=index&a=account_manage_password&t=account';
  static const forgotPassword =
      'index.php?m=member&c=index&a=public_forget_password&siteid=1';

  /// 图形验证码, 需要与提交请求共用同一份 cookie.
  static const checkCode =
      'api.php?op=checkcode&code_len=4&font_size=14'
      '&width=118&height=40&font_color=&background=';

  /// 私信, 需要登录态.
  static const messageList = 'index.php?m=message&c=index&a=inbox';
  static const messageDetail = 'index.php?m=message&c=index&a=read';
  static const messageSend = 'index.php?m=message&c=index&a=send';
  static const messageReply = 'index.php?m=message&c=index&a=reply';

  /// 系统公告, 与私信同属消息模块, 但是单向公告.
  ///
  /// 站点把公告挂在 group 系列动作下, 条目编号是 group_id,
  /// 只有列表与详情, 没有回复接口; 详情页需要 group_id 参数.
  static const messageGroupList = 'index.php?m=message&c=index&a=group';
  static const messageGroupDetail = 'index.php?m=message&c=index&a=read_group';

  /// 广告点击上报, 站点页面里的 adClick 打的是同一个地址.
  ///
  /// 站点只给登录访客的广告位挂上报脚本, 应用解析到登录标记后才调用这里.
  static const adClick = 'index.php?m=content&c=ad_click&a=init';

  /// 点击上报地址, 末尾的毫秒时间戳用于防缓存, 与站点页面一致.
  static String adClickUrl(String adId, {required int timestamp}) =>
      '$adClick&adid=${Uri.encodeQueryComponent(adId)}&t=$timestamp';

  /// 生成弹幕接口需要的播放器 id.
  ///
  /// 与官方 `generatePlayerId` 一致, 末尾的分P序号是弹幕的区分依据.
  static String playerId(int typeId, String hid, int part) =>
      '$typeId-$hid-1-$part';

  /// 生成评论接口需要的楼层 id.
  ///
  /// 与官方构造一致: `content_{typeid}-{hid}-1`, 末尾的 1 是固定值,
  /// 不是分P序号, 同一视频的所有分P共用同一个评论楼层.
  static String commentId(int typeId, String hid) => 'content_$typeId-$hid-1';

  static String playUrl(String hid) => '${Constants.baseUrl}play/h$hid/';

  /// 用户空间地址, 站点用 play/u{uid}/ 表示投稿人主页.
  static String userUrl(int userId) => 'play/u$userId/';
}
