import 'package:get/get.dart';
import 'package:tucao/pages/bgm/bgm_index_page.dart';
import 'package:tucao/pages/channel/channel_page.dart';
import 'package:tucao/pages/history/history_page.dart';
import 'package:tucao/pages/login/login_page.dart';
import 'package:tucao/pages/main/main_page.dart';
import 'package:tucao/pages/rank/hot_search_page.dart';
import 'package:tucao/pages/rank/rank_page.dart';
import 'package:tucao/pages/search/search_page.dart';
import 'package:tucao/pages/setting/setting_page.dart';
import 'package:tucao/pages/video/video_page.dart';
import 'package:tucao/router/routes.dart';

/// 路由登记.
abstract final class AppPages {
  static final List<GetPage> pages = [
    GetPage(name: Routes.main, page: () => const MainPage()),
    GetPage(name: Routes.channel, page: () => const ChannelPage()),
    GetPage(name: Routes.rank, page: () => const RankPage()),
    GetPage(name: Routes.search, page: () => const SearchPage()),
    GetPage(name: Routes.bgmIndex, page: () => const BgmIndexPage()),
    GetPage(name: Routes.video, page: () => const VideoPage()),
    GetPage(name: Routes.history, page: () => const HistoryPage()),
    GetPage(name: Routes.setting, page: () => const SettingPage()),
    GetPage(name: Routes.login, page: () => const LoginPage()),
    GetPage(name: Routes.hotSearch, page: () => const HotSearchPage()),
  ];
}
