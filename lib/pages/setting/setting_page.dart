import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tucao/common/style.dart';
import 'package:tucao/services/account_service.dart';
import 'package:tucao/services/history_service.dart';
import 'package:tucao/services/theme_service.dart';
import 'package:tucao/utils/logger.dart';
import 'package:tucao/utils/storage_pref.dart';

/// 设置页.
///
/// 开关与滑块都即时写入 [Pref], 页面内不再提供保存动作.
class SettingPage extends StatefulWidget {
  const SettingPage({super.key});

  @override
  State<SettingPage> createState() => _SettingPageState();
}

class _SettingPageState extends State<SettingPage> {
  /// 可选播放倍速.
  static const _speeds = <double>[0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

  /// 搜索历史条数上限.
  static const _historyLimits = <int>[10, 20, 50];

  final _theme = ThemeService.instance;

  late int _themeMode;
  late bool _dynamicColor;
  late int? _seedColor;

  late double _playerSpeed;
  late bool _autoPlay;
  late bool _continueLast;
  late bool _hardwareDecode;
  late bool _background;

  late bool _danmakuEnable;
  late double _danmakuOpacity;
  late double _danmakuFontSize;
  late double _danmakuArea;
  late double _danmakuSpeed;
  late double _danmakuStroke;
  late bool _hideScroll;
  late bool _hideTop;
  late bool _hideBottom;

  late int _searchHistoryLimit;

  @override
  void initState() {
    super.initState();
    _themeMode = _theme.themeMode.value;
    _dynamicColor = _theme.useDynamicColor.value;
    _seedColor = _theme.seedColor.value;

    _playerSpeed = _speeds.contains(Pref.playerSpeed) ? Pref.playerSpeed : 1.0;
    _autoPlay = Pref.playerAutoPlay;
    _continueLast = Pref.playerContinueLast;
    _hardwareDecode = Pref.hardwareDecode;
    _background = Pref.playerBackground;

    _danmakuEnable = Pref.danmakuEnable;
    _danmakuOpacity = Pref.danmakuOpacity;
    _danmakuFontSize = Pref.danmakuFontSize;
    _danmakuArea = Pref.danmakuArea;
    _danmakuSpeed = Pref.danmakuSpeed;
    _danmakuStroke = Pref.danmakuStroke;
    _hideScroll = Pref.danmakuHideScroll;
    _hideTop = Pref.danmakuHideTop;
    _hideBottom = Pref.danmakuHideBottom;

    // 旧版本可能存有不在预设里的值, 回落到默认档位.
    _searchHistoryLimit = _historyLimits.contains(Pref.searchHistoryLimit)
        ? Pref.searchHistoryLimit
        : 20;
  }

  /// 二次确认, 用户点取消时返回 false.
  Future<bool> _confirm({
    required String title,
    required String message,
    required String confirmText,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Get.back(result: true),
            child: Text(confirmText),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  void _setThemeMode(int value) {
    setState(() => _themeMode = value);
    _theme.setThemeMode(value);
  }

  void _setSeedColor(int? value) {
    setState(() => _seedColor = value);
    _theme.setSeedColor(value);
  }

  Future<void> _clearHistory() async {
    final ok = await _confirm(
      title: '清除播放历史',
      message: '将删除全部本地播放记录, 确定继续吗?',
      confirmText: '清除',
    );
    if (!ok || !mounted) {
      return;
    }
    await HistoryService.instance.clear();
    if (!mounted) {
      return;
    }
    Get.snackbar('已清除', '本地播放历史已清空');
  }

  Future<void> _logout() async {
    final ok = await _confirm(
      title: '退出登录',
      message: '将清除本地 cookie 与登录信息, 确定继续吗?',
      confirmText: '退出',
    );
    if (!ok || !mounted) {
      return;
    }
    try {
      await AccountService.instance.logout();
      if (!mounted) {
        return;
      }
      Get.snackbar('已退出登录', '本地登录信息与 cookie 已清除');
    } catch (e, stackTrace) {
      Log.e('退出登录失败', error: e, stackTrace: stackTrace);
      if (!mounted) {
        return;
      }
      Get.snackbar('退出登录失败', '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          const _SectionTitle('外观'),
          RadioGroup<int>(
            groupValue: _themeMode,
            onChanged: (value) => _setThemeMode(value ?? 0),
            child: const Column(
              children: [
                _ThemeModeTile(value: 0, label: '跟随系统'),
                _ThemeModeTile(value: 1, label: '浅色'),
                _ThemeModeTile(value: 2, label: '深色'),
              ],
            ),
          ),
          SwitchListTile(
            title: const Text('动态取色'),
            subtitle: const Text('使用系统壁纸提取的颜色, 自定义主题色优先'),
            value: _dynamicColor,
            onChanged: (value) {
              setState(() => _dynamicColor = value);
              _theme.setDynamicColor(value);
            },
          ),
          _ColorPicker(current: _seedColor, onChanged: _setSeedColor),

          const _SectionTitle('播放器'),
          ListTile(
            title: const Text('默认倍速'),
            trailing: DropdownButton<double>(
              value: _playerSpeed,
              underline: const SizedBox.shrink(),
              borderRadius: BorderRadius.circular(Style.cardRadius),
              items: [
                for (final speed in _speeds)
                  DropdownMenuItem(value: speed, child: Text('${speed}x')),
              ],
              onChanged: (value) {
                if (value == null) {
                  return;
                }
                setState(() => _playerSpeed = value);
                Pref.playerSpeed = value;
              },
            ),
          ),
          SwitchListTile(
            title: const Text('自动播放'),
            value: _autoPlay,
            onChanged: (value) {
              setState(() => _autoPlay = value);
              Pref.playerAutoPlay = value;
            },
          ),
          SwitchListTile(
            title: const Text('续播上次进度'),
            subtitle: const Text('进入播放页时跳转到上次观看的位置'),
            value: _continueLast,
            onChanged: (value) {
              setState(() => _continueLast = value);
              Pref.playerContinueLast = value;
            },
          ),
          SwitchListTile(
            title: const Text('硬件解码'),
            subtitle: const Text('关闭后改用软件解码, 画面异常时可尝试'),
            value: _hardwareDecode,
            onChanged: (value) {
              setState(() => _hardwareDecode = value);
              Pref.hardwareDecode = value;
            },
          ),
          SwitchListTile(
            title: const Text('后台播放'),
            subtitle: const Text('切到后台后继续播放声音'),
            value: _background,
            onChanged: (value) {
              setState(() => _background = value);
              Pref.playerBackground = value;
            },
          ),

          const _SectionTitle('弹幕'),
          SwitchListTile(
            title: const Text('显示弹幕'),
            value: _danmakuEnable,
            onChanged: (value) {
              setState(() => _danmakuEnable = value);
              Pref.danmakuEnable = value;
            },
          ),
          _SliderTile(
            label: '不透明度',
            value: _danmakuOpacity,
            min: 0.1,
            max: 1.0,
            divisions: 18,
            display: '${(_danmakuOpacity * 100).round()}%',
            onChanged: (value) {
              setState(() => _danmakuOpacity = value);
              Pref.danmakuOpacity = value;
            },
          ),
          _SliderTile(
            label: '字号',
            value: _danmakuFontSize,
            min: 8,
            max: 32,
            divisions: 24,
            display: _danmakuFontSize.round().toString(),
            onChanged: (value) {
              setState(() => _danmakuFontSize = value);
              Pref.danmakuFontSize = value;
            },
          ),
          _SliderTile(
            label: '显示区域',
            value: _danmakuArea,
            min: 0.1,
            max: 1.0,
            divisions: 18,
            display: '${(_danmakuArea * 100).round()}%',
            onChanged: (value) {
              setState(() => _danmakuArea = value);
              Pref.danmakuArea = value;
            },
          ),
          _SliderTile(
            label: '滚动时长',
            value: _danmakuSpeed,
            min: 4,
            max: 15,
            divisions: 22,
            display: '${_danmakuSpeed.toStringAsFixed(1)} 秒',
            onChanged: (value) {
              setState(() => _danmakuSpeed = value);
              Pref.danmakuSpeed = value;
            },
          ),
          _SliderTile(
            label: '描边宽度',
            value: _danmakuStroke,
            min: 0,
            max: 4,
            divisions: 8,
            display: _danmakuStroke.toStringAsFixed(1),
            onChanged: (value) {
              setState(() => _danmakuStroke = value);
              Pref.danmakuStroke = value;
            },
          ),
          SwitchListTile(
            title: const Text('屏蔽滚动弹幕'),
            value: _hideScroll,
            onChanged: (value) {
              setState(() => _hideScroll = value);
              Pref.danmakuHideScroll = value;
            },
          ),
          SwitchListTile(
            title: const Text('屏蔽顶部弹幕'),
            value: _hideTop,
            onChanged: (value) {
              setState(() => _hideTop = value);
              Pref.danmakuHideTop = value;
            },
          ),
          SwitchListTile(
            title: const Text('屏蔽底部弹幕'),
            value: _hideBottom,
            onChanged: (value) {
              setState(() => _hideBottom = value);
              Pref.danmakuHideBottom = value;
            },
          ),

          const _SectionTitle('其他'),
          ListTile(
            title: const Text('搜索历史条数上限'),
            trailing: SegmentedButton<int>(
              segments: [
                for (final limit in _historyLimits)
                  ButtonSegment(value: limit, label: Text('$limit')),
              ],
              selected: {_searchHistoryLimit},
              showSelectedIcon: false,
              onSelectionChanged: (selection) {
                final value = selection.first;
                setState(() => _searchHistoryLimit = value);
                Pref.searchHistoryLimit = value;
              },
            ),
          ),
          ListTile(
            title: const Text('清除播放历史'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _clearHistory,
          ),
          ListTile(
            title: const Text('清除 Cookie / 退出登录'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _logout,
          ),
        ],
      ),
    );
  }
}

/// 分组标题.
class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: scheme.primary,
        ),
      ),
    );
  }
}

/// 主题模式的单选项, 选项值由上层 [RadioGroup] 管理.
class _ThemeModeTile extends StatelessWidget {
  const _ThemeModeTile({required this.value, required this.label});

  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return RadioListTile<int>(value: value, title: Text(label), dense: true);
  }
}

/// 主题色圆点选择.
class _ColorPicker extends StatelessWidget {
  const _ColorPicker({required this.current, required this.onChanged});

  /// 当前种子色, 为空表示使用站点默认色.
  final int? current;

  final ValueChanged<int?> onChanged;

  /// 预设色, 取自 Material 调色板的常见色.
  static const _presets = <_PresetColor>[
    _PresetColor('红色', 0xFFE53935),
    _PresetColor('粉色', 0xFFE91E63),
    _PresetColor('紫色', 0xFF8E24AA),
    _PresetColor('靛蓝', 0xFF3949AB),
    _PresetColor('蓝色', 0xFF1E88E5),
    _PresetColor('青色', 0xFF00ACC1),
    _PresetColor('蓝绿', 0xFF00897B),
    _PresetColor('绿色', 0xFF43A047),
    _PresetColor('橙色', 0xFFFB8C00),
    _PresetColor('棕色', 0xFF6D4C41),
    _PresetColor('蓝灰', 0xFF546E7A),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('主题色', style: TextStyle(fontSize: 15, color: scheme.onSurface)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _Dot(
                color: Style.seedColor,
                selected: current == null,
                label: '默认',
                onTap: () => onChanged(null),
              ),
              for (final preset in _presets)
                _Dot(
                  color: Color(preset.value),
                  selected: current == preset.value,
                  label: preset.name,
                  onTap: () => onChanged(preset.value),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 预设色定义.
class _PresetColor {
  const _PresetColor(this.name, this.value);

  final String name;
  final int value;
}

/// 单个颜色圆点, 选中时显示对勾.
class _Dot extends StatelessWidget {
  const _Dot({
    required this.color,
    required this.selected,
    required this.label,
    required this.onTap,
  });

  static const _size = 34.0;

  final Color color;
  final bool selected;

  /// 无障碍与长按提示用的名称.
  final String label;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground =
        ThemeData.estimateBrightnessForColor(color) == Brightness.dark
        ? Colors.white
        : Colors.black87;
    return Tooltip(
      message: label,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: _size,
          height: _size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? scheme.onSurface : Colors.transparent,
              width: 2,
            ),
          ),
          child: selected
              ? Icon(Icons.check, size: 16, color: foreground)
              : null,
        ),
      ),
    );
  }
}

/// 带标题与数值显示的滑块.
class _SliderTile extends StatelessWidget {
  const _SliderTile({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.display,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;

  /// 右侧显示的当前值.
  final String display;

  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(label, style: const TextStyle(fontSize: 15)),
              ),
              Text(
                display,
                style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
          Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
