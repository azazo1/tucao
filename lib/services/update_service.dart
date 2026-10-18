import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:tucao/build_config.dart';
import 'package:tucao/http/update_http.dart';
import 'package:tucao/models/app_release.dart';
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

  /// 打开浏览器进入下载页.
  download,
}

/// 版本更新提示.
///
/// 只做提示与跳转: 查到 GitHub Release 上的新版本后给出发布页链接,
/// 下载与安装交给系统浏览器和安装器, 应用本身不申请安装权限.
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
    await _showDialog(context, release);
  }

  /// 手动检查, 无论用户是否跳过过该版本都给出结果.
  static Future<void> checkManually(BuildContext context) async {
    final current = await _currentVersion();
    AppRelease? release;
    try {
      release = await UpdateHttp.fetchLatest();
    } catch (error) {
      Log.w('检查更新失败: $error');
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('检查更新失败, 请稍后重试')));
      }
      return;
    }
    if (!context.mounted) {
      return;
    }
    if (release == null ||
        !Version.isNewer(current: current, candidate: release.tagName)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已是最新版本')));
      return;
    }
    await _showDialog(context, release);
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

  /// 更新提示对话框, 按用户选择决定是否记住该版本或打开浏览器.
  ///
  /// 手动检查同样走这里, 因此忽略过的版本在手动检查时还会出现.
  static Future<void> _showDialog(
    BuildContext context,
    AppRelease release,
  ) async {
    final choice = await showDialog<_UpdateChoice>(
      context: context,
      builder: (dialogContext) => AlertDialog(
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
                  '下载后在系统里覆盖安装即可, 不要先卸载, 卸载会清除本地数据.',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    color: Theme.of(dialogContext).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, _UpdateChoice.later),
            child: const Text('稍后'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, _UpdateChoice.ignore),
            child: const Text('忽略此版本'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, _UpdateChoice.download),
            child: const Text('前往下载'),
          ),
        ],
      ),
    );
    if (choice == _UpdateChoice.ignore) {
      Pref.skippedUpdateVersion = release.tagName;
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已忽略 ${release.tagName}, 发布新版本时会再次提示')),
        );
      }
      return;
    }
    if (choice == _UpdateChoice.download) {
      await _openPage(context, release);
    }
    // 选稍后或直接关闭时不做记录, 下次启动的自动检查会重新提示.
  }

  /// 用系统浏览器打开下载页.
  static Future<void> _openPage(
    BuildContext context,
    AppRelease release,
  ) async {
    try {
      final opened = await launchUrl(
        Uri.parse(release.pageUrl),
        mode: LaunchMode.externalApplication,
      );
      if (!opened && context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('未能打开浏览器, 请在项目页下载')));
      }
    } catch (error) {
      Log.w('打开下载页失败: $error');
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('无法打开浏览器')));
      }
    }
  }
}
