/// 弹幕条目.
class DanmakuModel {
  const DanmakuModel({
    required this.time,
    required this.mode,
    required this.fontSize,
    required this.color,
    required this.timestamp,
    required this.text,
  });

  /// 出现时间, 秒.
  final double time;

  /// 弹幕类型, 1 2 3 为滚动, 4 为底部, 5 为顶部, 7 为高级弹幕.
  final int mode;

  final int fontSize;

  /// 颜色, 十进制整数.
  final int color;

  /// 发送时间戳, 秒.
  final int timestamp;

  final String text;

  /// 站点弹幕的 p 属性格式:
  /// 时间, 类型, 字号, 颜色, 时间戳, 弹幕池, 用户id, 行id
  factory DanmakuModel.fromAttr(String attr, String text) {
    final parts = attr.split(',');
    double parseDouble(int index) =>
        index < parts.length ? double.tryParse(parts[index]) ?? 0 : 0;
    int parseInt(int index) =>
        index < parts.length ? int.tryParse(parts[index]) ?? 0 : 0;
    return DanmakuModel(
      time: parseDouble(0),
      mode: parseInt(1),
      fontSize: parseInt(2),
      color: parseInt(3),
      timestamp: parseInt(4),
      text: text,
    );
  }

  Map<String, dynamic> toJson() => {
    'time': time,
    'mode': mode,
    'fontSize': fontSize,
    'color': color,
    'timestamp': timestamp,
    'text': text,
  };

  factory DanmakuModel.fromJson(Map<String, dynamic> json) => DanmakuModel(
    time: (json['time'] as num?)?.toDouble() ?? 0,
    mode: (json['mode'] as num?)?.toInt() ?? 1,
    fontSize: (json['fontSize'] as num?)?.toInt() ?? 25,
    color: (json['color'] as num?)?.toInt() ?? 0xFFFFFF,
    timestamp: (json['timestamp'] as num?)?.toInt() ?? 0,
    text: json['text']?.toString() ?? '',
  );
}
