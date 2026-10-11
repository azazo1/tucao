import 'package:get/get.dart';

/// 页面路由.
///
/// 站点是单层 Tab 结构, 这里按页面职责登记路由, 参数通过 [Get.parameters] 传递.
abstract final class Routes {
  static const main = '/';
  static const video = '/video';
  static const search = '/search';
  static const rank = '/rank';
  static const channel = '/channel';
  static const setting = '/setting';
  static const login = '/login';
  static const history = '/history';
  static const bgmIndex = '/bgm';
  static const hotSearch = '/hot-search';
  static const data = '/data';
  static const article = '/article';
  static const space = '/space';
  static const weekBgm = '/week-bgm';
}

/// 路由过渡动画, 与站点轻量的观感一致.
class RouteTransition {
  static Transition get defaultTransition => Transition.cupertino;
}
