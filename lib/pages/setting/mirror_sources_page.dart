import 'package:flutter/material.dart';
import 'package:tucao/common/adaptive.dart';
import 'package:tucao/http/update_http.dart';
import 'package:tucao/models/update_mirror.dart';
import 'package:tucao/services/update/update_mirror_store.dart';
import 'package:tucao/services/update/update_speed_test.dart';
import 'package:tucao/utils/logger.dart';

/// 国内镜像源管理.
///
/// 列出可用的 GitHub 加速站, 可以逐条启用或停用, 也能添加自定义前缀.
/// 测速只读取安装包开头的一小段, 结果仅用于展示, 不改变下载顺序.
class MirrorSourcesPage extends StatefulWidget {
  const MirrorSourcesPage({super.key});

  @override
  State<MirrorSourcesPage> createState() => _MirrorSourcesPageState();
}

class _MirrorSourcesPageState extends State<MirrorSourcesPage> {
  /// 读不到最新发布时用这个地址测速, 它是仓库里一直保留的正式发布产物.
  static const _fallbackSpeedUrl =
      'https://github.com/azazo1/tucao/releases/download/'
      'v1.5.0/tucao-1.5.0-android-arm64-v8a.apk';

  late List<UpdateMirror> _mirrors;

  /// 以镜像前缀为键的测速结果.
  final _speeds = <String, MirrorSpeedResult>{};

  /// 正在测速的镜像前缀.
  final _measuring = <String>{};

  bool _testingAll = false;

  @override
  void initState() {
    super.initState();
    _mirrors = UpdateMirrorStore.read();
  }

  void _save() {
    UpdateMirrorStore.write(_mirrors);
  }

  void _setEnabled(int index, bool value) {
    setState(() => _mirrors[index] = _mirrors[index].copyWith(enabled: value));
    _save();
  }

  void _remove(int index) {
    final mirror = _mirrors[index];
    setState(() => _mirrors.removeAt(index));
    _speeds.remove(mirror.prefix);
    _save();
  }

  Future<void> _add() async {
    final input = await showDialog<String>(
      context: context,
      builder: (_) => const _AddMirrorDialog(),
    );
    if (input == null || !mounted) {
      return;
    }
    final prefix = UpdateMirror.normalizePrefix(input);
    final error = UpdateMirror.validatePrefix(prefix);
    if (error != null) {
      _toast(error);
      return;
    }
    if (_mirrors.any((mirror) => mirror.prefix == prefix)) {
      _toast('这个前缀已经在列表里了');
      return;
    }
    setState(() => _mirrors.add(UpdateMirror(prefix: prefix)));
    _save();
  }

  void _restoreDefaults() {
    setState(() {
      _mirrors = List.of(UpdateMirror.builtin);
      _speeds.clear();
    });
    UpdateMirrorStore.restoreDefaults();
    _toast('已恢复内置默认镜像源');
  }

  /// 测速用的安装包地址, 优先取最新正式发布的产物.
  Future<String> _speedTarget() async {
    try {
      final release = await UpdateHttp.fetchLatest();
      final assets = release?.assets;
      if (assets != null) {
        for (final asset in assets) {
          if (asset.name.toLowerCase().endsWith('.apk')) {
            return asset.downloadUrl;
          }
        }
      }
    } catch (error) {
      Log.w('读取测速用的安装包地址失败, 改用内置地址: $error');
    }
    return _fallbackSpeedUrl;
  }

  Future<void> _measure(UpdateMirror mirror, String targetUrl) async {
    if (_measuring.contains(mirror.prefix)) {
      return;
    }
    setState(() {
      _measuring.add(mirror.prefix);
      _speeds.remove(mirror.prefix);
    });
    final result = await UpdateSpeedTest.measure(
      mirror: mirror,
      targetUrl: targetUrl,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _measuring.remove(mirror.prefix);
      _speeds[mirror.prefix] = result;
    });
  }

  Future<void> _testAll() async {
    final enabled = [
      for (final mirror in _mirrors)
        if (mirror.enabled) mirror,
    ];
    if (enabled.isEmpty) {
      _toast('没有启用的镜像源, 先启用一个再测速');
      return;
    }
    if (_testingAll) {
      return;
    }
    setState(() => _testingAll = true);
    final targetUrl = await _speedTarget();
    for (final mirror in enabled) {
      if (!mounted) {
        return;
      }
      await _measure(mirror, targetUrl);
    }
    if (!mounted) {
      return;
    }
    setState(() => _testingAll = false);
  }

  Future<void> _testOne(UpdateMirror mirror) async {
    if (_testingAll || _measuring.contains(mirror.prefix)) {
      return;
    }
    await _measure(mirror, await _speedTarget());
  }

  void _toast(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabledCount = _mirrors.where((mirror) => mirror.enabled).length;
    // 宽屏下内容居中, 窄屏为 0; 列表自身靠 ListTile 的内边距,
    // 底栏不是 ListTile, 需要额外补 16 才能和列表内容对齐.
    final side = Adaptive.sidePadding(context, maxWidth: Adaptive.listMaxWidth);
    return Scaffold(
      appBar: AppBar(
        title: const Text('国内镜像源'),
        actions: [
          IconButton(
            tooltip: '测速',
            onPressed: _testingAll ? null : _testAll,
            icon: _testingAll
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.speed),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'restore') {
                _restoreDefaults();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'restore', child: Text('恢复内置默认源')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              '下载更新包时按列表顺序尝试启用的镜像, 都失败才改用 GitHub 官方源. '
              '点条目可以给该镜像测速.',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: _mirrors.isEmpty
                ? const Center(child: Text('还没有任何镜像源'))
                : ListView.separated(
                    padding: EdgeInsets.symmetric(
                      horizontal: side,
                      vertical: 4,
                    ),
                    itemCount: _mirrors.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final mirror = _mirrors[index];
                      return _MirrorRow(
                        mirror: mirror,
                        speed: _speeds[mirror.prefix],
                        measuring: _measuring.contains(mirror.prefix),
                        onEnabledChanged: (value) => _setEnabled(index, value),
                        onMeasure: () => _testOne(mirror),
                        onRemove: () => _remove(index),
                      );
                    },
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              // sidePadding 只是宽屏下的居中留白, 窄屏为 0,
              // 这里不是 ListTile, 需要自己补上页面边距.
              padding: EdgeInsets.fromLTRB(16 + side, 8, 16 + side, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '共 ${_mirrors.length} 个, 启用 $enabledCount 个',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _add,
                    icon: const Icon(Icons.add),
                    label: const Text('添加镜像源'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 镜像源列表里的一行.
class _MirrorRow extends StatelessWidget {
  const _MirrorRow({
    required this.mirror,
    required this.speed,
    required this.measuring,
    required this.onEnabledChanged,
    required this.onMeasure,
    required this.onRemove,
  });

  final UpdateMirror mirror;
  final MirrorSpeedResult? speed;
  final bool measuring;
  final ValueChanged<bool> onEnabledChanged;
  final VoidCallback onMeasure;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final detail = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    return ListTile(
      onTap: onMeasure,
      title: Text(mirror.prefix),
      subtitle: Row(
        children: [
          if (measuring) ...[
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 1.5),
            ),
            const SizedBox(width: 6),
            Text('测速中', style: detail),
          ] else if (speed != null)
            Flexible(
              child: Text(
                speed!.ok
                    ? '${speed!.text}, 首字节 ${_milliseconds(speed!.firstByte)}'
                    : speed!.text,
                style: detail?.copyWith(
                  color: speed!.ok ? scheme.primary : scheme.error,
                ),
              ),
            )
          else
            Text('点击测速', style: detail),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Switch(value: mirror.enabled, onChanged: onEnabledChanged),
          IconButton(
            tooltip: '删除',
            onPressed: onRemove,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
    );
  }

  static String _milliseconds(Duration? value) =>
      value == null ? '未知' : '${value.inMilliseconds}ms';
}

/// 添加镜像源的输入框, 只校验形状, 重复与保存由页面负责.
class _AddMirrorDialog extends StatefulWidget {
  const _AddMirrorDialog();

  @override
  State<_AddMirrorDialog> createState() => _AddMirrorDialogState();
}

class _AddMirrorDialogState extends State<_AddMirrorDialog> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final error = UpdateMirror.validatePrefix(_controller.text);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.pop(context, _controller.text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('添加镜像源'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.url,
        decoration: InputDecoration(
          labelText: '镜像前缀',
          hintText: 'https://gh-proxy.com',
          errorText: _error,
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('添加')),
      ],
    );
  }
}
