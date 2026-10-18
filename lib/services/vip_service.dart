import 'package:get/get.dart';
import 'package:tucao/http/api_path.dart';
import 'package:tucao/http/vip_http.dart';
import 'package:tucao/utils/logger.dart';

/// 评论区的破会员标记.
///
/// 评论 json 接口没有会员字段, 标记只能从评论页 HTML 里解析, 见 [VipHttp].
/// 这里把各页解析出来的 uid 攒起来, 供评论列表查询, 同一页在 [pageTtl] 内
/// 不会重复请求.
///
/// 站点以后若在评论 json 里补上会员字段, 这个服务可以整体去掉, 评论列表也
/// 就不用额外抓页面了.
class VipService extends GetxController {
  /// 服务未注册时返回空, 便于在测试里只构造控制器.
  static VipService? get maybe =>
      Get.isRegistered<VipService>() ? Get.find<VipService>() : null;

  /// 同一页评论的重复抓取间隔.
  static const pageTtl = Duration(minutes: 10);

  /// 已知的破会员 uid, 可观察, 标记到位后评论列表会自己刷新.
  final vipUids = <int>{}.obs;

  /// 各页最近一次抓取时间, 键是 `评论楼层#页码`.
  final _pages = <String, DateTime>{};

  /// uid 是否是已知的破会员, 未知的评论者返回 false.
  bool isVip(int uid) => uid > 0 && vipUids.contains(uid);

  /// 记录某一页评论里的破会员.
  ///
  /// 标记属于锦上添花, 因此失败只记日志, 不影响评论列表, 并且不占用
  /// 重复抓取间隔, 下次翻到这一页时还会再试.
  Future<void> rememberCommentPage({
    required int typeId,
    required String hid,
    int page = 1,
  }) async {
    final commentId = ApiPath.commentId(typeId, hid);
    final key = '$commentId#$page';
    final now = DateTime.now();
    final last = _pages[key];
    if (last != null && now.difference(last) < pageTtl) {
      return;
    }
    _pages[key] = now;
    try {
      final uids = await VipHttp.fetchCommentVipUids(
        typeId: typeId,
        hid: hid,
        page: page,
      );
      if (uids.isEmpty) {
        return;
      }
      vipUids.addAll(uids);
      Log.i('评论页第 $page 页标记破会员 ${uids.length} 人');
    } catch (e) {
      _pages.remove(key);
      Log.w('获取评论页会员标记失败 commentid=$commentId page=$page: $e');
    }
  }
}
