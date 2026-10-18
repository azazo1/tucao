import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tucao/models/cast_device.dart';
import 'package:tucao/services/cast/discovery.dart';
import 'package:tucao/utils/logger.dart';

/// 搜索并选择投屏设备.
///
/// 返回选中的设备, 用户取消或没有设备时返回空.
Future<CastDevice?> showCastDeviceSheet(
  BuildContext context, {
  CastDiscovery? discovery,
}) {
  return showModalBottomSheet<CastDevice>(
    context: context,
    showDragHandle: true,
    builder: (_) => _CastDeviceSheet(discovery: discovery ?? CastDiscovery()),
  );
}

class _CastDeviceSheet extends StatefulWidget {
  const _CastDeviceSheet({required this.discovery});

  final CastDiscovery discovery;

  @override
  State<_CastDeviceSheet> createState() => _CastDeviceSheetState();
}

class _CastDeviceSheetState extends State<_CastDeviceSheet> {
  List<CastDevice> _devices = const [];
  bool _scanning = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_scan());
  }

  @override
  void dispose() {
    // 搜索是一次性的, 关掉弹层时把内部的 http 客户端一起收掉.
    widget.discovery.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    setState(() {
      _scanning = true;
      _error = null;
    });
    try {
      final devices = await widget.discovery.search();
      if (!mounted) {
        return;
      }
      setState(() {
        _devices = devices;
        _scanning = false;
      });
    } catch (error, stackTrace) {
      Log.w('搜索投屏设备失败: $error');
      if (!mounted) {
        return;
      }
      setState(() {
        _scanning = false;
        _error = '搜索失败, 请检查 Wi-Fi 后重试';
      });
      Log.e('搜索投屏设备异常', error: error, stackTrace: stackTrace);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: SizedBox(
        height: 360,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 8, 4),
              child: Row(
                children: [
                  Text('投屏到电视', style: theme.textTheme.titleMedium),
                  const Spacer(),
                  IconButton(
                    tooltip: '重新搜索',
                    onPressed: _scanning ? null : _scan,
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
            ),
            Expanded(child: _buildBody(theme)),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                '手机与电视需在同一 Wi-Fi. 投屏期间画面由电视播放, 弹幕不会显示.',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_scanning) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            ),
            SizedBox(height: 12),
            Text('正在搜索同网段的电视…'),
          ],
        ),
      );
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!),
            const SizedBox(height: 8),
            TextButton(onPressed: _scan, child: const Text('重试')),
          ],
        ),
      );
    }
    if (_devices.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            '没有找到可投屏设备.\n确认电视已开机, 与手机连同一个 Wi-Fi, '
            '路由器没有开启 AP 隔离.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      itemCount: _devices.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final device = _devices[index];
        return ListTile(
          leading: const Icon(Icons.tv),
          title: Text(device.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(device.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
          onTap: () => Navigator.of(context).pop(device),
        );
      },
    );
  }
}
