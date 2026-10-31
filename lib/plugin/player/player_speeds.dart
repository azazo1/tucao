/// 播放器与设置页共用的倍速选项.
abstract final class PlayerSpeeds {
  /// 控制条与默认倍速可选的档位.
  static const options = <double>[0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 2.5, 3.0];

  /// 长按临时加速可选的档位.
  static const longPressOptions = <double>[2.0, 3.0, 4.0];

  static const defaultLongPress = 3.0;

  /// 倍速文本, 整数档位不带小数, 比如 `2x`, `1.25x`.
  static String label(double speed) {
    final text = speed == speed.roundToDouble()
        ? speed.toStringAsFixed(0)
        : speed.toString();
    return '${text}x';
  }
}
