/// 发送弹幕时的位置, [code] 是站点接口的 mode 取值.
enum DanmakuSendMode {
  scroll(1, '滚动'),
  top(5, '顶部'),
  bottom(4, '底部');

  const DanmakuSendMode(this.code, this.label);

  final int code;
  final String label;
}

/// 发送弹幕的样式: 位置与颜色.
///
/// 只在本次运行内记住, 不写入配置.
class DanmakuSendStyle {
  const DanmakuSendStyle({
    this.mode = DanmakuSendMode.scroll,
    this.color = defaultColor,
  });

  static const defaultColor = 0xFFFFFF;

  /// 可选颜色, 不带透明度, 与站点按十进制整数提交的格式一致.
  static const colors = [
    0xFFFFFF,
    0xFE0302,
    0xFF7204,
    0xFFD302,
    0xA0EE00,
    0x00CD00,
    0x89D5FF,
    0x4266BE,
    0xCC0273,
    0x9B9B9B,
  ];

  final DanmakuSendMode mode;

  /// 弹幕颜色, `0xRRGGBB`.
  final int color;

  DanmakuSendStyle copyWith({DanmakuSendMode? mode, int? color}) {
    return DanmakuSendStyle(
      mode: mode ?? this.mode,
      color: color ?? this.color,
    );
  }
}
