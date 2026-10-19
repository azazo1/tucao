import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:tucao/models/release_asset.dart';
import 'package:tucao/models/update_download.dart';
import 'package:tucao/services/update/update_download_service.dart';
import 'package:tucao/services/update/update_transport.dart';

class _Transport implements UpdateTransport {
  final calls = <Uri>[];

  /// 省略时按 [defaultBytes] 直接写满整个文件.
  Future<int> Function(File target, CancelToken token)? behavior;

  List<int> defaultBytes = const [1, 2, 3];

  @override
  Future<int> fetch({
    required Uri uri,
    required File target,
    required CancelToken cancelToken,
    required void Function(int received, int total) onProgress,
  }) async {
    calls.add(uri);
    final custom = behavior;
    if (custom != null) {
      return custom(target, cancelToken);
    }
    await target.writeAsBytes(defaultBytes, flush: true);
    onProgress(defaultBytes.length, defaultBytes.length);
    return defaultBytes.length;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late Directory directory;
  late _Transport transport;
  late UpdateDownloadService service;

  List<ReleaseAsset> apks({required int size}) => [
    ReleaseAsset(
      name: 'tucao-1.3.0-android-armeabi-v7a.apk',
      size: size,
      downloadUrl: 'https://example.com/v7a.apk',
    ),
    ReleaseAsset(
      name: 'tucao-1.3.0-android-arm64-v8a.apk',
      size: size,
      downloadUrl: 'https://example.com/arm64.apk',
    ),
  ];

  setUp(() async {
    final temporary = Directory(
      path.join(Directory.current.path, '.tmp'),
    ).absolute;
    await temporary.create(recursive: true);
    root = await temporary.createTemp('update-download-');
    directory = Directory(path.join(root.path, 'updates'));
    transport = _Transport();
    service = UpdateDownloadService(
      transport: transport,
      location: () async => directory,
    );
  });

  tearDown(() async {
    service.onClose();
    final temporary = path.normalize(
      path.join(Directory.current.absolute.path, '.tmp'),
    );
    final target = path.normalize(root.absolute.path);
    expect(path.isWithin(temporary, target), isTrue);
    await root.delete(recursive: true);
  });

  test('按设备 ABI 顺序挑包, 下载完成后落到更新目录', () async {
    await service.start(
      version: 'v1.3.0',
      assets: apks(size: 3),
      abis: ['arm64-v8a', 'armeabi-v7a'],
    );
    final ready = service.state.value;
    expect(ready.status, UpdateDownloadStatus.ready);
    expect(transport.calls.single.path, '/arm64.apk');
    expect(path.basename(ready.path), 'tucao-1.3.0-android-arm64-v8a.apk');
    expect(await File(ready.path).readAsBytes(), [1, 2, 3]);
    // 同一个包已经下好, 再点一次不会重复请求.
    await service.start(
      version: 'v1.3.0',
      assets: apks(size: 3),
      abis: ['arm64-v8a', 'armeabi-v7a'],
    );
    expect(transport.calls.length, 1);
  });

  test('设备没有对应的安装包时直接失败, 不发请求', () async {
    await service.start(version: 'v1.3.0', assets: apks(size: 3), abis: ['x86']);
    expect(service.state.value.status, UpdateDownloadStatus.failed);
    expect(service.state.value.error, contains('适配'));
    expect(transport.calls, isEmpty);
  });

  test('字节数与发布记录不一致时判失败并清掉半成品', () async {
    await service.start(
      version: 'v1.3.0',
      assets: apks(size: 5),
      abis: ['arm64-v8a'],
    );
    final failed = service.state.value;
    expect(failed.status, UpdateDownloadStatus.failed);
    expect(failed.error, contains('不一致'));
    expect(failed.received, 0);
    expect(await directory.list().toList(), isEmpty);
  });

  test('中断下载丢弃半成品, 重新下载从头开始', () async {
    final started = Completer<void>();
    transport.behavior = (target, token) async {
      await target.writeAsBytes([1, 2], flush: true);
      started.complete();
      throw await token.whenCancel;
    };
    final running = service.start(
      version: 'v1.3.0',
      assets: apks(size: 3),
      abis: ['arm64-v8a'],
    );
    await started.future;
    await service.pause();
    await running;
    expect(service.state.value.status, UpdateDownloadStatus.paused);
    expect((await directory.list().toList()).whereType<File>(), isEmpty);
    transport.behavior = null;
    await service.retry();
    expect(service.state.value.status, UpdateDownloadStatus.ready);
    expect(transport.calls.length, 2);
  });

  test('放弃任务后目录与状态都清空', () async {
    await service.start(
      version: 'v1.3.0',
      assets: apks(size: 3),
      abis: ['arm64-v8a'],
    );
    expect(service.state.value.status, UpdateDownloadStatus.ready);
    await service.discard();
    expect(service.state.value.status, UpdateDownloadStatus.idle);
    expect(await directory.list().toList(), isEmpty);
  });
}
