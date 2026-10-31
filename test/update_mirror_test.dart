import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:tucao/models/update_mirror.dart';
import 'package:tucao/services/update/update_mirror_store.dart';
import 'package:tucao/utils/storage.dart';

class _Settings implements Box {
  final data = <dynamic, dynamic>{};
  final changes = StreamController<BoxEvent>.broadcast(sync: true);

  @override
  dynamic get(dynamic key, {dynamic defaultValue}) => data[key] ?? defaultValue;
  @override
  bool containsKey(dynamic key) => data.containsKey(key);
  @override
  Future<void> put(dynamic key, dynamic value) async {
    data[key] = value;
    changes.add(BoxEvent(key, value, false));
  }

  @override
  Stream<BoxEvent> watch({dynamic key}) => changes.stream;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Settings box;

  setUp(() {
    box = _Settings();
    GStorage.setting = box;
  });

  test('前缀规范化与校验', () {
    expect(
      UpdateMirror.normalizePrefix('  https://a.example//  '),
      'https://a.example',
    );
    expect(UpdateMirror.validatePrefix('https://a.example'), isNull);
    expect(UpdateMirror.validatePrefix('http://a.example'), isNull);
    expect(UpdateMirror.validatePrefix('ftp://a.example'), isNotNull);
    expect(UpdateMirror.validatePrefix('a.example'), isNotNull);
    expect(UpdateMirror.validatePrefix(''), isNotNull);
    expect(UpdateMirror.validatePrefix('https://a.example/?x=1'), isNotNull);
    expect(UpdateMirror.validatePrefix('https://a.example/#tag'), isNotNull);
  });

  test('json 还原时缺省启用, 坏前缀被丢弃', () {
    expect(
      UpdateMirror.fromJson({'prefix': 'https://a.example'})?.enabled,
      isTrue,
    );
    expect(
      UpdateMirror.fromJson({
        'prefix': 'https://a.example',
        'enabled': false,
      })?.enabled,
      isFalse,
    );
    expect(UpdateMirror.fromJson({'prefix': 'nope'}), isNull);
    expect(UpdateMirror.fromJson({'prefix': 1}), isNull);
    expect(UpdateMirror.fromJson('bad'), isNull);
  });

  test('保存后读回顺序与开关', () {
    UpdateMirrorStore.write(const [
      UpdateMirror(prefix: 'https://a.example'),
      UpdateMirror(prefix: 'https://b.example', enabled: false),
    ]);
    final restored = UpdateMirrorStore.read();
    expect(
      [for (final mirror in restored) mirror.prefix],
      ['https://a.example', 'https://b.example'],
    );
    expect(restored.last.enabled, isFalse);
    expect(UpdateMirrorStore.enabledPrefixes(), ['https://a.example']);
    expect(UpdateMirrorStore.hasEnabled, isTrue);
  });

  test('重复前缀只保留一条', () {
    UpdateMirrorStore.write(const [
      UpdateMirror(prefix: 'https://a.example'),
      UpdateMirror(prefix: 'https://a.example', enabled: false),
    ]);
    expect(UpdateMirrorStore.read(), hasLength(1));
    expect(UpdateMirrorStore.read().single.enabled, isTrue);
  });

  test('没有保存过时使用内置默认源', () {
    final list = UpdateMirrorStore.read();
    expect(list, hasLength(UpdateMirror.builtin.length));
    expect(list.single.prefix, UpdateMirror.builtin.single.prefix);
    expect(UpdateMirrorStore.hasEnabled, isTrue);
  });

  test('版本不符或配置损坏时回落默认', () {
    box.data['update_mirrors'] = jsonEncode({
      'version': 99,
      'mirrors': [
        {'prefix': 'https://a.example', 'enabled': true},
      ],
    });
    expect(
      UpdateMirrorStore.read().single.prefix,
      UpdateMirror.builtin.single.prefix,
    );

    box.data['update_mirrors'] = '{oops';
    expect(UpdateMirrorStore.read(), hasLength(UpdateMirror.builtin.length));
  });

  test('用户删光镜像后保持为空', () {
    UpdateMirrorStore.write(const []);
    expect(UpdateMirrorStore.read(), isEmpty);
    expect(UpdateMirrorStore.enabledPrefixes(), isEmpty);
    expect(UpdateMirrorStore.hasEnabled, isFalse);
  });

  test('恢复内置默认源', () {
    UpdateMirrorStore.write(const []);
    UpdateMirrorStore.restoreDefaults();
    expect(UpdateMirrorStore.read().single.prefix, 'https://gh-proxy.com');
  });
}
