import 'package:flutter/material.dart';
import 'package:tucao/models/danmaku_preferences.dart';
import 'package:tucao/utils/danmaku_preferences_store.dart';
import 'package:tucao/utils/logger.dart';

Future<void> showDanmakuSettingsSheet(
  BuildContext context, {
  ValueChanged<DanmakuPreferences>? onChanged,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.85,
      child: DanmakuSettingsPanel(
        initial: DanmakuPreferencesStore.read(),
        unsupportedVersion: DanmakuPreferencesStore.hasUnsupportedVersion,
        onChanged: onChanged,
      ),
    ),
  );
}

/// 设置页和播放器共用. 滑条拖动预览, 松手后等待持久化结果.
class DanmakuSettingsPanel extends StatefulWidget {
  const DanmakuSettingsPanel({
    super.key,
    required this.initial,
    this.onChanged,
    this.save = DanmakuPreferencesStore.save,
    this.unsupportedVersion = false,
  });

  final DanmakuPreferences initial;
  final ValueChanged<DanmakuPreferences>? onChanged;
  final Future<void> Function(DanmakuPreferences) save;
  final bool unsupportedVersion;

  @override
  State<DanmakuSettingsPanel> createState() => _DanmakuSettingsPanelState();
}

class _DanmakuSettingsPanelState extends State<DanmakuSettingsPanel> {
  late DanmakuPreferences _value;
  late DanmakuPreferences _saved;
  bool _saving = false;
  bool _pendingRollback = false;
  String? _error;
  bool get _editable => !_saving && !widget.unsupportedVersion;
  bool get _current => mounted && (ModalRoute.of(context)?.isCurrent ?? true);

  @override
  void initState() {
    super.initState();
    _value = widget.initial.normalized;
    _saved = _value;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_pendingRollback && _current) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_pendingRollback && _current) {
          _pendingRollback = false;
          widget.onChanged?.call(_saved);
        }
      });
    }
  }

  void _preview(DanmakuPreferences value) {
    if (!_editable || !_current) return;
    setState(() {
      _value = value.normalized;
      _pendingRollback = false;
      _error = null;
    });
    widget.onChanged?.call(_value);
  }

  Future<void> _commit() async {
    if (!_editable || !_current) return;
    final value = _value;
    setState(() => _saving = true);
    try {
      await widget.save(value);
      if (!mounted) return;
      _saved = value;
    } catch (error, stackTrace) {
      Log.e('保存弹幕样式失败', error: error, stackTrace: stackTrace);
      if (!mounted) return;
      final current = _current;
      setState(() {
        _value = _saved;
        _pendingRollback = !current;
        _error = current ? '保存失败, 已恢复原设置. 请重试.' : null;
      });
      if (current) widget.onChanged?.call(_saved);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _change(DanmakuPreferences value) {
    _preview(value);
    _commit();
  }

  Future<void> _reset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('恢复弹幕默认样式'),
        content: const Text('仅恢复弹幕样式和类型开关, 确定继续吗?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('恢复')),
        ],
      ),
    );
    if (confirmed == true && _current) _change(DanmakuPreferences.defaults);
  }

  Widget _heading(String title) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
    child: Text(title, style: TextStyle(
      color: Theme.of(context).colorScheme.primary,
      fontWeight: FontWeight.w600,
    )),
  );

  Widget _slider({
    required String name, required double value, required double min,
    required double max, required int divisions, required String display,
    required DanmakuPreferences Function(double) update, String? help,
  }) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 12, runSpacing: 4, children: [Text(name), Text(display)]),
      if (help != null) Text(help, style: Theme.of(context).textTheme.bodySmall),
      Slider(
        key: ValueKey('danmaku-$name'),
        value: value,
        min: min,
        max: max,
        divisions: divisions,
        label: display,
        onChanged: _editable ? (value) => _preview(update(value)) : null,
        onChangeEnd: _editable ? (_) => _commit() : null,
      ),
    ]),
  );

  Widget _switch(String name, bool value, DanmakuPreferences Function(bool) update,
      {String? help}) => SwitchListTile(
    title: Text(name),
    subtitle: help == null ? null : Text(help),
    value: value,
    onChanged: _editable ? (value) => _change(update(value)) : null,
  );

  @override
  Widget build(BuildContext context) {
    final value = _value;
    return ListView(
      key: const ValueKey('danmaku-settings-scroll'),
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Wrap(alignment: WrapAlignment.spaceBetween, spacing: 12, children: [
            Text('弹幕设置', style: Theme.of(context).textTheme.titleLarge),
            TextButton.icon(
              onPressed: _editable ? _reset : null,
              icon: const Icon(Icons.restore), label: const Text('恢复默认'),
            ),
          ]),
        ),
        if (_saving) const LinearProgressIndicator(),
        if (widget.unsupportedVersion) const Padding(
          padding: EdgeInsets.all(16),
          child: Text('弹幕设置来自更新的版本, 原数据已保留. 请使用支持该版本的应用修改.'),
        ),
        if (_error != null) Padding(
          padding: const EdgeInsets.all(16),
          child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: DanmakuStylePreview(preferences: value),
        ),
        _switch('显示弹幕', value.enabled, (v) => value.copyWith(enabled: v)),
        _heading('文字样式'),
        _slider(name: '不透明度', value: value.opacity, min: 0, max: 1,
          divisions: 100, display: '${(value.opacity * 100).round()}%',
          update: (v) => value.copyWith(opacity: v)),
        _slider(name: '字号', value: value.fontSize, min: 8, max: 40,
          divisions: 32, display: '${value.fontSize.round()} px',
          update: (v) => value.copyWith(fontSize: v)),
        _slider(name: '字重', value: value.fontWeight.toDouble(), min: 0, max: 8,
          divisions: 8, display: '${(value.fontWeight + 1) * 100}',
          help: '字体支持的粗细可能因设备不同而变化',
          update: (v) => value.copyWith(fontWeight: v.round())),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('字体'),
            DropdownButton<String>(
              isExpanded: true,
              value: value.fontFamily ?? 'default',
              items: const [
                DropdownMenuItem(value: 'default', child: Text('默认字体')),
                DropdownMenuItem(value: 'sans-serif', child: Text('系统无衬线')),
              ],
              onChanged: _editable ? (v) {
                if (v == null) return;
                _change(value.copyWith(fontFamily: v == 'default' ? null : v,
                  clearFontFamily: v == 'default'));
              } : null,
            ),
          ]),
        ),
        _slider(name: '描边宽度', value: value.strokeWidth, min: 0, max: 5,
          divisions: 10, display: '${value.strokeWidth.toStringAsFixed(1)} px',
          update: (v) => value.copyWith(strokeWidth: v)),
        _slider(name: '行高', value: value.lineHeight, min: 1, max: 3,
          divisions: 20, display: '${value.lineHeight.toStringAsFixed(1)} 倍',
          update: (v) => value.copyWith(lineHeight: v)),
        _heading('运动与布局'),
        _slider(name: '滚动时长', value: value.duration, min: 1, max: 30,
          divisions: 58, display: '${value.duration.toStringAsFixed(1)} 秒',
          help: '从右到左经过画面的时间, 时间越短速度越快',
          update: (v) => value.copyWith(duration: v)),
        _slider(name: '固定弹幕时长', value: value.staticDuration, min: 1, max: 30,
          divisions: 58, display: '${value.staticDuration.toStringAsFixed(1)} 秒',
          update: (v) => value.copyWith(staticDuration: v)),
        _slider(name: '显示区域', value: value.area, min: 0.1, max: 1,
          divisions: 18, display: '${(value.area * 100).round()}%',
          update: (v) => value.copyWith(area: v)),
        _switch('字幕避让', value.safeArea, (v) => value.copyWith(safeArea: v),
          help: '为画面底部字幕预留空间'),
        _switch('允许弹幕重叠', value.massiveMode, (v) => value.copyWith(massiveMode: v),
          help: '轨道占满后继续显示, 可能影响阅读'),
        _heading('弹幕类型'),
        _switch('滚动弹幕', !value.hideScroll, (v) => value.copyWith(hideScroll: !v)),
        _switch('顶部弹幕', !value.hideTop, (v) => value.copyWith(hideTop: !v)),
        _switch('底部弹幕', !value.hideBottom, (v) => value.copyWith(hideBottom: !v)),
      ],
    );
  }
}

/// 在小区域内展示真实字体, 描边, 行高与透明度.
class DanmakuStylePreview extends StatelessWidget {
  const DanmakuStylePreview({super.key, required this.preferences});
  final DanmakuPreferences preferences;

  Widget _sample(String text, DanmakuPreferences value) {
    final style = TextStyle(
      fontSize: value.fontSize,
      fontWeight: FontWeight.values[value.fontWeight],
      fontFamily: value.fontFamily,
      height: value.lineHeight,
    );
    return Opacity(
      opacity: value.enabled ? value.opacity : 0,
      child: Stack(children: [
        Text(text, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: style.copyWith(foreground: Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = value.strokeWidth
            ..color = Colors.black)),
        Text(text, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: style.copyWith(color: Colors.white)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final value = preferences.normalized;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('文字样式预览'),
      const SizedBox(height: 8),
      ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 140,
          width: double.infinity,
          color: const Color(0xFF455A64),
          child: Stack(children: [
            FractionallySizedBox(
              widthFactor: 1, heightFactor: value.area,
              child: ColoredBox(color: Colors.white.withValues(alpha: 0.08)),
            ),
            if (!value.hideTop) Align(alignment: Alignment.topCenter,
              child: _sample('顶部弹幕', value)),
            if (!value.hideScroll) Align(alignment: Alignment.centerLeft,
              child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12),
                child: _sample('滚动弹幕样式', value))),
            if (!value.hideBottom) Align(alignment: Alignment.bottomCenter,
              child: Padding(padding: EdgeInsets.only(bottom: value.safeArea ? 24 : 0),
                child: _sample('底部弹幕', value))),
            if (value.safeArea) const Align(alignment: Alignment.bottomCenter,
              child: SizedBox(height: 24, child: Center(
                child: Text('字幕预留区域', style: TextStyle(color: Colors.white70, fontSize: 11))))),
          ]),
        ),
      ),
    ]);
  }
}
