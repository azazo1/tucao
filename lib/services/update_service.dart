import 'dart:async';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:tucao/build_config.dart';
import 'package:tucao/common/constants.dart';
import 'package:tucao/http/update_http.dart';
import 'package:tucao/models/app_release.dart';
import 'package:tucao/models/dev_build.dart';
import 'package:tucao/models/release_asset.dart';
import 'package:tucao/models/update_download.dart';
import 'package:tucao/services/update/update_download_service.dart';
import 'package:tucao/services/update/update_installer.dart';
import 'package:tucao/utils/logger.dart';
import 'package:tucao/utils/storage_pref.dart';
import 'package:tucao/utils/version.dart';
import 'package:url_launcher/url_launcher.dart';

/// 更新提示对话框的选择.
enum _UpdateChoice {
  /// 本次不处理, 下次启动仍会提示.
  later,

  /// 记住该版本, 自动检查不再提示.
  ignore,

  /// 在应用内下载安装包.
  download,

  /// 打开浏览器进入发布页, 由用户自己挑产物.
  page,
}

/// 版本更新提示.
///
/// 查到 GitHub Release 上的新版本后, 在对话框里展示发布说明并按设备 ABI
/// 挑出对应的安装包. 下载在应用内进行, 完成后交给系统安装器;
/// 没有匹配的产物, 或者用户更想自己下载时, 仍然可以跳到发布页.

abstract final class UpdateService {
  /// 本次启动是否已经自动检查过, 避免每次回到首页都发请求.
  static bool _startupChecked = false;

  /// 启动后自动检查一次, 用户跳过的版本不再重复提示.
  ///
  /// 失败只记日志, 不影响其他功能.
  static Future<void> checkOnStartup(BuildContext context) async {
    if (_startupChecked) {
      return;
    }
    _startupChecked = true;
    final release = await _fetchNewer();
    if (release == null || !context.mounted) {
      return;
    }
    if (Pref.skippedUpdateVersion == release.tagName) {
      return;
    }
    final message = await _showDialog(context, release);
    if (message != null && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  /// 手动检查, 无论用户是否跳过过该版本都给出结果.
  ///
  /// 返回值是本次要提示给用户的文案, 由调用方决定显示位置: 关于对话框把它
  /// 显示在框内, 因此这里不再自己弹提示条, 免得被对话框挡住.
  /// 发现新版本时返回更新对话框给出的结果, 不需要补充提示时返回 null.
  static Future<String?> checkManually(BuildContext context) async {
    final current = await _currentVersion();
    AppRelease? release;
    try {
      release = await UpdateHttp.fetchLatest();
    } catch (error) {
      Log.w('检查更新失败: $error');
      return '检查更新失败, 请稍后重试';
    }
    if (!context.mounted) {
      return null;
    }
    if (release == null ||
        !Version.isNewer(current: current, candidate: release.tagName)) {
      return '已是最新版本';
    }
    return _showDialog(context, release);
  }

  /// 手动检查 CI 上的开发版构建, 返回需要提示给用户的文案.
  ///
  /// 开发版是分支推送产生的滚动预发布, 产物会被后续推送覆盖,
  /// 因此只比较注入的版本串, 不提供"忽略此版本".
  static Future<String?> checkDevManually(BuildContext context) async {
    DevBuild? build;
    try {
      build = await UpdateHttp.fetchDevLatest();
    } catch (error) {
      Log.w('检查开发版更新失败: $error');
      return '检查开发版更新失败, 请稍后重试';
    }
    if (!context.mounted) {
      return null;
    }
    if (build == null) {
      return '没能读取 CI 上的开发版信息';
    }
    Log.i('CI 开发版 ${build.buildVersion}, 当前构建 ${BuildConfig.buildVersion}');
    await _showDevDialog(context, build);
    return null;
  }

  /// 查询比当前版本新的发布, 没有或请求失败时返回 null.
  static Future<AppRelease?> _fetchNewer() async {
    final current = await _currentVersion();
    try {
      final release = await UpdateHttp.fetchLatest();
      if (release == null ||
          !Version.isNewer(current: current, candidate: release.tagName)) {
        return null;
      }
      Log.i('发现新版本 ${release.tagName}, 当前版本 $current');
      return release;
    } catch (error) {
      Log.w('自动检查更新失败: $error');
      return null;
    }
  }

  /// 当前版本号.
  ///
  /// 发布构建带注入的构建版本, 日常开发构建没有注入, 退回包版本.
  static Future<String> _currentVersion() async {
    if (BuildConfig.buildVersion != 'dev-build') {
      return BuildConfig.buildVersion;
    }
    try {
      final info = await PackageInfo.fromPlatform();
      return info.version;
    } catch (error) {
      // 读不到包版本时按 0 处理, 至少不会因为比较失败而弹更新.
      Log.w('读取包版本失败: $error');
      return '0.0.0';
    }
  }

  /// 对话框动作按钮的紧凑样式.
  ///
  /// AlertDialog 把动作交给 OverflowBar, 一排排不下时会把按钮竖着摞起来,
  /// 窄屏上 "稍后 / 忽略此版本 / 下载" 正好越过这条线. M3 的按钮各自带
  /// 64 的最小宽度与 16 到 24 的横向内边距, 收掉最小宽度并把内边距统一到
  /// 12 之后, 一排留出两成以上的余量, 系统字号放大一档也还排得下.
  static ButtonStyle _actionStyle({bool filled = false}) {
    const padding = EdgeInsets.symmetric(horizontal: 12);
    const minimumSize = Size(0, 40);
    return filled
        ? FilledButton.styleFrom(padding: padding, minimumSize: minimumSize)
        : TextButton.styleFrom(padding: padding, minimumSize: minimumSize);
  }

  /// 更新提示对话框, 按用户选择决定是否记住该版本或开始应用内下载.
  ///
  /// 手动检查同样走这里, 因此忽略过的版本在手动检查时还会出现.
  /// 返回对话框之后还要提示给用户的文案.
  static Future<String?> _showDialog(
    BuildContext context,
    AppRelease release,
  ) async {
    // 设备 ABI 决定取哪个安装包, 本机没有对应产物时只留发布页入口.
    final abis = await UpdateInstaller.supportedAbis();
    if (!context.mounted) {
      return null;
    }
    final asset = release.apkFor(abis);
    final choice = await showDialog<_UpdateChoice>(
      context: context,
      builder: (dialogContext) {
        final scheme = Theme.of(dialogContext).colorScheme;
        final noteStyle = TextStyle(
          fontSize: 12,
          height: 1.5,
          color: scheme.onSurfaceVariant,
        );
        return AlertDialog(
          title: Text('发现新版本 ${release.tagName}'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    release.body.trim().isEmpty
                        ? '该版本没有填写发布说明.'
                        : release.body.trim(),
                    style: const TextStyle(fontSize: 13, height: 1.5),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    asset == null
                        ? '没有找到适配本机的安装包, 请到发布页里选择.'
                        : '应用内下载 ${asset.name} (${asset.sizeText}), '
                              '下载完成后在"关于"里点安装.',
                    style: noteStyle,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '安装时系统会要求允许本应用安装未知应用; 覆盖安装即可, '
                    '不要先卸载, 卸载会清除本地数据.',
                    style: noteStyle,
                  ),
                  const SizedBox(height: 12),
                  Text('备用下载地址:', style: noteStyle),
                  _linkRow(dialogContext, release.pageUrl, noteStyle),
                  const SizedBox(height: 4),
                  _linkRow(dialogContext, Constants.officialSiteUrl, noteStyle),
                  Text(
                    '官网下载页并非本人管理, 链接可能随时撤去, 也可能更新延迟.',
                    style: noteStyle,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              style: _actionStyle(),
              onPressed: () =>
                  Navigator.pop(dialogContext, _UpdateChoice.later),
              child: const Text('稍后'),
            ),
            TextButton(
              style: _actionStyle(),
              onPressed: () =>
                  Navigator.pop(dialogContext, _UpdateChoice.ignore),
              child: const Text('忽略此版本'),
            ),
            FilledButton(
              style: _actionStyle(filled: true),
              onPressed: () => Navigator.pop(
                dialogContext,
                asset == null ? _UpdateChoice.page : _UpdateChoice.download,
              ),
              child: Text(asset == null ? '前往发布页' : '下载'),
            ),
          ],
        );
      },
    );
    if (!context.mounted) {
      return null;
    }
    if (choice == _UpdateChoice.ignore) {
      Pref.skippedUpdateVersion = release.tagName;
      return '已忽略 ${release.tagName}, 发布新版本时会再次提示';
    }
    if (choice == _UpdateChoice.page) {
      await _openUrl(context, release.pageUrl);
      return null;
    }
    if (choice == _UpdateChoice.download) {
      _startDownload(
        context,
        version: release.tagName,
        assets: release.assets,
        pageUrl: release.pageUrl,
        abis: abis,
      );
    }
    // 选稍后或直接关闭时不做记录, 下次启动的自动检查会重新提示.
    return null;
  }

  /// 开始应用内下载.
  ///
  /// 对话框此时已经关掉, 下载在服务里继续, 进度与安装入口都在关于对话框里,
  /// 因此这里只提示用户去哪里接着看, 并顺手给一个即时的取消入口.
  static void _startDownload(
    BuildContext context, {
    required String version,
    required List<ReleaseAsset> assets,
    required String pageUrl,
    required List<String> abis,
  }) {
    final download = UpdateDownloadService.maybeInstance;
    if (download == null) {
      // 下载服务没有就绪时退回发布页, 不让更新入口失效.
      unawaited(_openUrl(context, pageUrl));
      return;
    }
    final current = download.state.value;
    if (current.version == version) {
      if (current.status == UpdateDownloadStatus.ready) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('安装包已经下好, 在"关于"里点安装')),
        );
        return;
      }
      if (current.isDownloading) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('安装包正在下载, 进度在"关于"里查看')),
        );
        return;
      }
    }
    unawaited(download.start(version: version, assets: assets, abis: abis));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('已开始下载安装包, 进度在"关于"里查看'),
        action: SnackBarAction(
          label: '取消',
          onPressed: () => unawaited(download.pause()),
        ),
      ),
    );
  }

  /// 对话框里的下载地址链接.
  static Widget _linkRow(
    BuildContext context,
    String url,
    TextStyle style,
  ) {
    return InkWell(
      onTap: () => _openUrl(context, url),
      child: Text(
        url,
        style: style.copyWith(
          color: Theme.of(context).colorScheme.primary,
          decoration: TextDecoration.underline,
        ),
      ),
    );
  }

  /// 开发版检查结果对话框.
  ///
  /// 结果显示当前构建与 CI 构建的版本串, 只有 CI 上有另一份构建时
  /// 才给出下载入口; 本地构建没有注入版本号时无法比较, 也允许直接去下载.
  static Future<void> _showDevDialog(
    BuildContext context,
    DevBuild build,
  ) async {
    // 与正式版同一套挑选逻辑, 产物同样按架构分开.
    final abis = await UpdateInstaller.supportedAbis();
    if (!context.mounted) {
      return;
    }
    final asset = build.apkFor(abis);
    final current = BuildConfig.buildVersion;
    final status = build.statusFor(current);
    final canDownload =
        status == DevBuildStatus.outdated || status == DevBuildStatus.unknown;
    final download = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final scheme = Theme.of(dialogContext).colorScheme;
        final noteStyle = TextStyle(
          fontSize: 12,
          height: 1.5,
          color: scheme.onSurfaceVariant,
        );
        return AlertDialog(
          title: Text(switch (status) {
            DevBuildStatus.latest => '开发版已是最新',
            DevBuildStatus.localNewer => '当前构建比 CI 开发版新',
            DevBuildStatus.outdated => '发现新的开发版',
            DevBuildStatus.unknown => 'CI 上的最新开发版',
          }),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '当前构建: ${_describeVersion(current)}',
                    style: const TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'CI 构建: ${build.buildVersion.isEmpty ? '未读取到版本号' : build.buildVersion}',
                    style: const TextStyle(fontSize: 13),
                  ),
                  if (status == DevBuildStatus.latest) ...[
                    const SizedBox(height: 8),
                    Text('与本机版本一致, 不需要重新下载.', style: noteStyle),
                  ],
                  if (status == DevBuildStatus.unknown) ...[
                    const SizedBox(height: 8),
                    Text(
                      build.buildVersion.isEmpty
                          ? 'CI 说明里没有写出版本号, 无法判断是否同一份构建.'
                          : '本地构建没有注入版本号, 无法判断是否同一份构建.',
                      style: noteStyle,
                    ),
                  ],
                  if (build.body.trim().isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      build.body.trim(),
                      style: const TextStyle(fontSize: 12, height: 1.5),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Text(
                    asset == null
                        ? '没有找到适配本机的安装包, 请到发布页里选择.'
                        : '应用内下载 ${asset.name} (${asset.sizeText}), '
                              '下载完成后在"关于"里点安装.',
                    style: noteStyle,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '开发版由 CI 从分支构建, 每条说明与产物都会被后续推送覆盖; '
                    '安装时系统会要求允许本应用安装未知应用, 覆盖安装即可.',
                    style: noteStyle,
                  ),
                  const SizedBox(height: 12),
                  Text('发布页:', style: noteStyle),
                  _linkRow(dialogContext, build.pageUrl, noteStyle),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              style: _actionStyle(),
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('关闭'),
            ),
            if (canDownload)
              FilledButton(
                style: _actionStyle(filled: true),
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(asset == null ? '前往发布页' : '下载'),
              ),
          ],
        );
      },
    );
    if (download != true) {
      return;
    }
    if (asset == null) {
      await _openUrl(context, build.pageUrl);
      return;
    }
    _startDownload(
      context,
      version: 'dev-latest',
      assets: build.assets,
      pageUrl: build.pageUrl,
      abis: abis,
    );
  }

  /// 对话框里的当前构建说明, 本地开发构建没有注入版本号.
  static String _describeVersion(String version) =>
      version == 'dev-build' ? '本地开发构建 (未注入版本号)' : version;

  /// 用系统浏览器打开链接, 失败时给出提示.
  static Future<void> _openUrl(BuildContext context, String url) async {
    try {
      final opened = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!opened && context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('未能打开浏览器, 请手动访问链接')));
      }
    } catch (error) {
      Log.w('打开链接失败: $error');
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('无法打开浏览器')));
      }
    }
  }
}
