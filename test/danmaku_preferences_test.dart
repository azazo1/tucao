import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:tucao/models/danmaku_preferences.dart';
import 'package:tucao/utils/danmaku_preferences_store.dart';
import 'package:tucao/utils/storage.dart';
import 'package:tucao/utils/storage_pref.dart';

class _Settings implements Box {
  final data = <dynamic, dynamic>{};
  final changes = StreamController<BoxEvent>.broadcast(sync: true);
  final writes = <Map>[];
  bool fail = false;

  @override
  dynamic get(dynamic key, {dynamic defaultValue}) => data[key] ?? defaultValue;
  @override
  bool containsKey(dynamic key) => data.containsKey(key);
  @override
  Future<void> put(dynamic key, dynamic value) async {
    if (fail) throw StateError('storage failure');
    data[key] = value;
    if (value is Map) writes.add(Map.of(value));
    changes.add(BoxEvent(key, value, false));
  }

  @override
  Stream<BoxEvent> watch({dynamic key}) => changes.stream;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('实际数据边界和类型校验避免无效选项', () {
    final p = DanmakuPreferences.fromMap({
      'opacity': double.nan,
      'fontSize': double.infinity,
      'fontWeight': 99,
      'area': -10,
      'duration': 0,
      'staticDuration': '5',
      'strokeWidth': 999,
      'lineHeight': -1,
      'safeArea': 'false',
      'enabled': 0,
      'hideTop': true,
      'fontFamily': 'unavailable-font',
    });
    expect(p.opacity, 1);
    expect(p.fontSize, 16);
    expect(p.fontWeight, 8);
    expect(p.area, 0.1);
    expect(p.duration, 1);
    expect(p.staticDuration, 5);
    expect(p.strokeWidth, 5);
    expect(p.lineHeight, 1);
    expect(p.safeArea, isTrue);
    expect(p.enabled, isTrue);
    expect(p.hideTop, isTrue);
    expect(p.fontFamily, isNull);
    final disabled = p.copyWith(enabled: false).toOption();
    expect(disabled.opacity, 0);
    expect(disabled.fontWeight, 8);
    expect(disabled.staticDuration, 5);
    expect(DanmakuPreferences.fromMap({'fontWeight': 2.5}).fontWeight, 4);
  });

  test('旧九键迁移保留数值语义且兼容setter串行合并', () async {
    final box = _Settings();
    GStorage.setting = box;
    box.data.addAll({
      'danmaku_enable': false,
      'danmaku_opacity': 0.35,
      'danmaku_font_size': 22,
      'danmaku_area': 0.7,
      'danmaku_speed': 12,
      'danmaku_stroke': 2,
      'danmaku_hide_scroll': true,
      'danmaku_hide_top': false,
      'danmaku_hide_bottom': true,
      'theme_mode': 2,
    });
    final old = DanmakuPreferencesStore.read();
    expect(old.duration, 12);
    expect(old.fontSize, 22);
    expect(old.enabled, isFalse);
    expect(old.hideScroll, isTrue);
    expect(old.hideBottom, isTrue);
    Pref.danmakuEnable = true;
    Pref.danmakuFontSize = 25;
    final finalValue = old.copyWith(
      enabled: true,
      fontSize: 25,
      staticDuration: 9,
    );
    await DanmakuPreferencesStore.save(finalValue);
    final restored = DanmakuPreferencesStore.read();
    expect(restored.toMap(), finalValue.toMap());
    expect(box.writes[1]['enabled'], isTrue);
    expect(box.writes[2]['enabled'], isTrue);
    expect(box.writes[2]['fontSize'], 25);
    expect(box.data[DanmakuPreferencesStore.key]['version'], 1);
    expect(box.data['theme_mode'], 2);
    expect(box.data['danmaku_speed'], 12);
    await box.changes.close();
  });

  test('未知新schema原样保留, 写入失败不能覆盖已保存设置', () async {
    final box = _Settings();
    GStorage.setting = box;
    final unknown = {'version': 2, 'opaque': 'keep'};
    box.data[DanmakuPreferencesStore.key] = unknown;
    expect(DanmakuPreferencesStore.hasUnsupportedVersion, isTrue);
    expect(DanmakuPreferencesStore.read().fontSize, 16);
    await expectLater(
      DanmakuPreferencesStore.save(DanmakuPreferences.defaults),
      throwsStateError,
    );
    expect(box.data[DanmakuPreferencesStore.key], same(unknown));
    box.data[DanmakuPreferencesStore.key] = const DanmakuPreferences(
      fontSize: 19,
    ).toMap();
    box.fail = true;
    await expectLater(
      DanmakuPreferencesStore.save(const DanmakuPreferences(fontSize: 28)),
      throwsStateError,
    );
    expect(DanmakuPreferencesStore.read().fontSize, 19);
    box.fail = false;
    final event = DanmakuPreferencesStore.watch().first;
    await DanmakuPreferencesStore.save(const DanmakuPreferences(fontSize: 21));
    expect((await event).fontSize, 21);
    await box.changes.close();
  });
}
