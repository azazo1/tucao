import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:tucao/models/video.dart';
import 'package:tucao/services/history_service.dart';
import 'package:tucao/utils/storage.dart';

class _Box implements Box {
  final data = <dynamic, dynamic>{};

  @override
  dynamic get(dynamic key, {dynamic defaultValue}) => data[key] ?? defaultValue;
  @override
  Future<void> put(dynamic key, dynamic value) async => data[key] = value;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

VideoModel _video(String hid) => VideoModel(hid: hid, title: hid);

void main() {
  test('卡片查询的索引跟着记录, 删除与清空刷新, 不返回过期数据', () async {
    GStorage.history = _Box();
    final service = HistoryService()..onInit();
    expect(service.latestOf('a'), isNull);

    await service.record(
      video: _video('a'),
      part: 0,
      progress: 50,
      duration: 100,
    );
    await service.record(
      video: _video('a'),
      part: 1,
      progress: 95,
      duration: 100,
    );
    await service.record(
      video: _video('b'),
      part: 0,
      progress: 1,
      duration: 100,
    );
    expect(service.latestOf('a')?.part, 1);
    expect(service.partsOf('a').keys, unorderedEquals([0, 1]));
    expect(service.partsOf('a')[1]?.finished, isTrue);
    expect(service.partsOf('a')[0]?.finished, isFalse);

    await service.remove(service.latestOf('a')!);
    expect(service.latestOf('a')?.part, 0);
    expect(service.partsOf('a').keys, [0]);

    await service.clear();
    expect(service.latestOf('b'), isNull);
    expect(service.partsOf('a'), isEmpty);
  });
}
