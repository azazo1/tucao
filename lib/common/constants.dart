import 'package:tucao/build_config.dart';

/// 项目级常量. 站点接口大部分沿用官方安卓端的定义, 见 ApiConfig.
abstract final class Constants {
  static const appName = '吐槽';
  static const sourceCodeUrl = 'https://github.com/azazo1/tucao';
  static const refererSourceCodeUrl = 'https://github.com/blackbbc/Tucao';

  /// 官方安卓端使用的接口密钥, 全站公开.
  static const apiKey = '25tids8f1ew1821ed';

  /// 主站域名, 构建时可用 SITE 覆盖为备用域名.
  static const defaultHost = 'www.tucao.my';

  static String get host =>
      BuildConfig.site.isEmpty ? defaultHost : BuildConfig.site;

  static String get baseUrl => 'https://$host/';

  static String get apiUrl => '${baseUrl}api_v2/';

  /// 播放页使用的浏览器 UA, 部分接口按 UA 返回不同内容.
  static const userAgent =
      'Mozilla/5.0 (Linux; Android 12; Pixel 6) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.6099.230 Mobile Safari/537.36';

  /// 桌面浏览器 UA.
  ///
  /// 排行榜等 html 页面按 UA 裁剪内容, 只有桌面 UA 才能拿到
  /// 今天/本周/本月/今年 四个时间维度的完整榜单.
  static const desktopUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  /// 分区列表, 与官网导航保持一致.
  static const channelList = <List<int>>[
    [24, 11, 43, 26, 10],
    [23, 39, 38, 16],
    [19, 28, 6, 29],
  ];

  /// 视频详情返回的占位封面.
  static const placeholderImage =
      'https://$defaultHost/uploadfile/2023/0823/20230823080102905.png';
}
