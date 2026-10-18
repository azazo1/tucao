import 'package:flutter/material.dart';

/// 站点 "破会员" 的判定与呈现约定.
///
/// 站点的会员信息目前有两个来源:
/// - `api.php?op=user` 返回的 `vip` 字段, 值为 `"1"` 表示当前登录用户是破会员.
///   该接口忽略 uid 参数, 只能查自己, 见 [fromApiValue].
/// - 网页端给破会员的昵称加 `#c07c32` 颜色 (会员特权里的 "亮眼"), 出现在
///   服务端渲染的评论页与用户空间页, 见 [hasNicknameColor].
///
/// 评论 json 接口不带会员字段, 只是在评论者没有设置昵称时会把整条用户记录
/// 塞进 `nickname` 字段, 那里面才有 `vip`; 因此评论区的标记目前靠抓评论页
/// 的颜色.
///
/// 站点接口以后若有变化, 改动集中在本文件:
/// - 若 `vip` 字段改名或改成其它取值 (例如字符串化的布尔), 只需调整
///   [fromApiValue], 上层都通过它判断.
/// - 若评论 json 接口以后给每条评论补上会员字段 (vip / groupid / 昵称颜色),
///   应当优先使用该字段, 并去掉 `VipHttp` 里额外的评论页请求, 见
///   [lib/http/vip_http.dart](../../http/vip_http.dart) 的说明.
/// - 若站点更换会员昵称颜色, 只需修改 [nicknameColor], 颜色比较与评论区的渲染
///   都用它; 我的页面与用户空间页按客户端金色呈现, 改观感只动 [gold] 这一组.
abstract final class Vip {
  /// 破会员昵称在站点网页端使用的颜色, 与 `#c07c32` 一致.
  ///
  /// 这是站点的身份标记色, 判定会员和"与网页端保持一致"的地方用它, 例如
  /// 评论区的昵称; 客户端自己的破会员观感走 [goldDeep] 这一套金色, 见
  /// [lib/common/widgets/vip_gold.dart](../../common/widgets/vip_gold.dart).
  static const nicknameColor = Color(0xFFC07C32);

  /// 客户端金色流光的色板.
  ///
  /// 从暗到亮依次是底色, 主色, 亮部与扫光高光, 流光渐变按这个顺序铺开.
  /// 命名与站点的会员色 [nicknameColor] 分开, 是因为站点色只用来认人, 客户端的
  /// 展示颜色可以随观感调整, 两者互不影响.
  static const goldDeep = Color(0xFFCF9420);

  /// 金色主色, 标签的底色也由它调出来.
  static const gold = Color(0xFFFFD24A);

  /// 扫光带两侧的亮部.
  static const goldBright = Color(0xFFFFE9A6);

  /// 扫光最亮处与粒子的颜色, 接近白.
  static const goldShine = Color(0xFFFFFCF0);

  /// 昵称颜色的小写十六进制写法, 站点写在 style 里.
  static const nicknameHex = '#c07c32';

  /// 同样的颜色写成 rgb 时的几种常见形式, 页面被浏览器重写样式后仍可识别.
  static const _nicknameRgbForms = [
    'rgb(192, 124, 50)',
    'rgb(192,124,50)',
    'rgba(192, 124, 50, 1)',
  ];

  /// 接口给出的 vip 值是否表示破会员.
  ///
  /// 站点返回的是字符串 `"1"`, 这里同时接受数字与布尔, 便于接口调整后兼容.
  static bool fromApiValue(Object? raw) {
    if (raw == null) {
      return false;
    }
    if (raw is bool) {
      return raw;
    }
    if (raw is num) {
      return raw != 0;
    }
    final text = raw.toString().trim().toLowerCase();
    return text == '1' || text == 'true';
  }

  /// 昵称样式里是否带破会员颜色.
  ///
  /// [style] 可以是元素的 style 属性, 也可以是单独的颜色值.
  static bool hasNicknameColor(String? style) {
    if (style == null || style.isEmpty) {
      return false;
    }
    final text = style.toLowerCase();
    if (text.contains(nicknameHex)) {
      return true;
    }
    return _nicknameRgbForms.any(text.contains);
  }
}
