import 'package:flutter/material.dart';
import 'package:tucao/common/site_host.dart';
import 'package:tucao/utils/storage_pref.dart';

/// 主站域名设置.
///
/// 站点换域名时用户不必等新版应用, 但网络层在启动时按域名拼接地址,
/// 因此保存后需要重启应用才生效.
class SiteHostTile extends StatefulWidget {
  const SiteHostTile({super.key});

  @override
  State<SiteHostTile> createState() => _SiteHostTileState();
}

class _SiteHostTileState extends State<SiteHostTile> {
  /// 已保存的域名, 为空表示跟随构建时或默认域名.
  late String _saved;

  @override
  void initState() {
    super.initState();
    _saved = Pref.siteHost;
  }

  Future<void> _edit() async {
    final saved = await showDialog<String>(
      context: context,
      builder: (_) => _SiteHostDialog(
        initial: _saved.isEmpty ? SiteHost.host : _saved,
      ),
    );
    if (saved == null || !mounted) {
      return;
    }
    Pref.siteHost = saved;
    setState(() => _saved = saved);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          saved.isEmpty ? '已恢复默认域名, 重启应用后生效' : '已保存域名, 重启应用后生效',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      title: const Text('站点域名'),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_saved.isEmpty ? SiteHost.host : _saved),
          Text(
            _saved.isEmpty ? '当前使用默认域名' : '重启应用后生效',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: _edit,
    );
  }
}

/// 域名输入对话框, 保存时返回整理后的域名, 恢复默认时返回空串.
class _SiteHostDialog extends StatefulWidget {
  const _SiteHostDialog({required this.initial});

  final String initial;

  @override
  State<_SiteHostDialog> createState() => _SiteHostDialogState();
}

class _SiteHostDialogState extends State<_SiteHostDialog> {
  late final TextEditingController _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initial);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final raw = _controller.text.trim();
    if (raw.isEmpty) {
      Navigator.pop(context, '');
      return;
    }
    final normalized = SiteHost.normalize(raw);
    if (normalized == null) {
      setState(() => _error = '请输入形如 ${SiteHost.defaultHost} 的域名');
      return;
    }
    Navigator.pop(context, normalized);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('站点域名'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(
              hintText: SiteHost.defaultHost,
              errorText: _error,
            ),
            onChanged: (_) {
              if (_error != null) {
                setState(() => _error = null);
              }
            },
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: 8),
          Text(
            '只填域名, 不要带协议和路径. 修改后需要重启应用才生效, '
            '切换域名后可能需要重新登录.',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, ''),
          child: const Text('恢复默认'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _save, child: const Text('保存')),
      ],
    );
  }
}
