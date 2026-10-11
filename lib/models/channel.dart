/// 站点分区.
class ChannelModel {
  const ChannelModel({
    required this.id,
    required this.name,
    this.children = const [],
  });

  final int id;
  final String name;

  /// 子分区, 顶级分区才有.
  final List<ChannelModel> children;

  factory ChannelModel.fromJson(Map<String, dynamic> json) {
    final rawChildren = json['children'];
    return ChannelModel(
      id: int.tryParse(json['id']?.toString() ?? '') ?? 0,
      name: json['name']?.toString() ?? '',
      children: rawChildren is List
          ? rawChildren
                .whereType<Map>()
                .map((e) => ChannelModel.fromJson(e.cast<String, dynamic>()))
                .toList()
          : const [],
    );
  }
}

/// 首页固定分区树, 与官网导航保持一致.
abstract final class ChannelData {
  static const List<ChannelModel> list = [
    ChannelModel(
      id: 24,
      name: '新番',
      children: [
        ChannelModel(id: 11, name: '连载新番'),
        ChannelModel(id: 43, name: '天朝出品'),
        ChannelModel(id: 26, name: '剧场版'),
        ChannelModel(id: 10, name: '完结番组'),
      ],
    ),
    ChannelModel(
      id: 23,
      name: '影剧',
      children: [
        ChannelModel(id: 39, name: '电视剧'),
        ChannelModel(id: 38, name: '电影'),
        ChannelModel(id: 16, name: '综艺娱乐'),
      ],
    ),
    ChannelModel(
      id: 19,
      name: '综合',
      children: [
        ChannelModel(id: 28, name: '动画'),
        ChannelModel(id: 6, name: '音乐'),
        ChannelModel(id: 29, name: '游戏'),
      ],
    ),
  ];

  /// 首页顶部分页用到的分区顺序.
  static final List<ChannelModel> homeTabs = [
    for (final channel in list) ...[channel, ...channel.children],
  ];

  static ChannelModel? find(int id) {
    for (final channel in homeTabs) {
      if (channel.id == id) {
        return channel;
      }
    }
    return null;
  }
}
