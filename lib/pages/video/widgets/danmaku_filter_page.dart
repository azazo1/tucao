import 'package:flutter/material.dart';
import 'package:tucao/models/danmaku_filter.dart';
import 'package:tucao/utils/danmaku_filter_store.dart';
import 'package:tucao/utils/logger.dart';

/// 打开弹幕屏蔽设置页, 设置页与播放器的弹幕面板共用.
Future<void> openDanmakuFilterPage(BuildContext context) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (context) => DanmakuFilterPage(
        initial: DanmakuFilterStore.read(),
        unsupportedVersion: DanmakuFilterStore.hasUnsupportedVersion,
      ),
    ),
  );
}

/// 屏蔽词增删与重复弹幕合并开关, 每次修改立即保存, 播放中的视频跟着生效.
class DanmakuFilterPage extends StatefulWidget {
  const DanmakuFilterPage({
    super.key,
    required this.initial,
    this.save = DanmakuFilterStore.save,
    this.unsupportedVersion = false,
  });

  final DanmakuFilter initial;
  final Future<void> Function(DanmakuFilter) save;
  final bool unsupportedVersion;

  @override
  State<DanmakuFilterPage> createState() => _DanmakuFilterPageState();
}

class _DanmakuFilterPageState extends State<DanmakuFilterPage> {
  late DanmakuFilter _value = widget.initial;
  final _input = TextEditingController();
  String? _inputError;
  String? _saveError;

  bool get _editable => !widget.unsupportedVersion;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _update(DanmakuFilter next) async {
    final previous = _value;
    setState(() {
      _value = next;
      _saveError = null;
    });
    try {
      await widget.save(next);
    } catch (error, stackTrace) {
      Log.e('保存弹幕屏蔽设置失败', error: error, stackTrace: stackTrace);
      if (!mounted) return;
      setState(() {
        _value = previous;
        _saveError = '保存失败, 已恢复原设置. 请重试.';
      });
    }
  }

  void _add() {
    final keyword = _input.text.trim();
    if (keyword.isEmpty) return;
    String? error;
    if (keyword.length > DanmakuFilter.maxKeywordLength) {
      error = '屏蔽词最多 ${DanmakuFilter.maxKeywordLength} 个字';
    } else if (!DanmakuFilter.isValidKeyword(keyword)) {
      error = '正则表达式写法有误';
    } else if (_value.keywords.contains(keyword)) {
      error = '已经添加过了';
    }
    if (error != null) {
      setState(() => _inputError = error);
      return;
    }
    Log.i('添加弹幕屏蔽词: $keyword');
    _input.clear();
    setState(() => _inputError = null);
    _update(_value.copyWith(keywords: [..._value.keywords, keyword]));
  }

  void _remove(String keyword) {
    Log.i('移除弹幕屏蔽词: $keyword');
    _update(
      _value.copyWith(
        keywords: _value.keywords.where((item) => item != keyword).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final keywords = _value.keywords;
    return Scaffold(
      appBar: AppBar(title: const Text('弹幕屏蔽')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          if (widget.unsupportedVersion)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('屏蔽设置来自更新的版本, 原数据已保留. 请使用支持该版本的应用修改.'),
            ),
          if (_saveError != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(_saveError!, style: TextStyle(color: scheme.error)),
            ),
          SwitchListTile(
            title: const Text('合并重复弹幕'),
            subtitle: const Text('10 秒内内容相同的弹幕只显示一条, 刷屏较多时标注条数'),
            value: _value.mergeDuplicates,
            onChanged: _editable
                ? (v) => _update(_value.copyWith(mergeDuplicates: v))
                : null,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              key: const ValueKey('danmaku-filter-input'),
              controller: _input,
              enabled: _editable,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _add(),
              onChanged: (_) {
                if (_inputError != null) setState(() => _inputError = null);
              },
              decoration: InputDecoration(
                labelText: '添加屏蔽词',
                helperText: '包含即屏蔽, 不区分大小写. 用 / 包起来按正则匹配, 例如 /^前方高能/',
                helperMaxLines: 2,
                errorText: _inputError,
                suffixIcon: IconButton(
                  onPressed: _editable ? _add : null,
                  icon: const Icon(Icons.add),
                  tooltip: '添加',
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              '已屏蔽 ${keywords.length} 个',
              style: TextStyle(
                color: scheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (keywords.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                '还没有屏蔽词',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final keyword in keywords)
                    InputChip(
                      label: Text(keyword),
                      avatar: DanmakuFilter.isRegex(keyword)
                          ? const Icon(Icons.code, size: 16)
                          : null,
                      onDeleted: _editable ? () => _remove(keyword) : null,
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
