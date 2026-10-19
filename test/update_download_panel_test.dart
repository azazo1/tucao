import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:tucao/models/update_download.dart';
import 'package:tucao/pages/mine/widgets/update_download_panel.dart';
import 'package:tucao/services/update/update_download_service.dart';
import 'package:tucao/services/update/update_transport.dart';

/// 这套用例不真的下载, 传输层只是服务构造需要的占位.
class _Transport implements UpdateTransport {
  @override
  Future<int> fetch({
    required Uri uri,
    required File target,
    required CancelToken cancelToken,
    required void Function(int received, int total) onProgress,
  }) async => 0;
}

/// 服务的 retry 要陪跑整个下载, 这里用永不完成的 Future 复现下载仍在进行.
class _Service extends UpdateDownloadService {
  _Service()
    : super(transport: _Transport(), location: () async => Directory('.tmp'));

  final _running = Completer<void>();
  int pauses = 0;

  @override
  Future<void> retry() {
    state.value = const UpdateDownloadState(
      status: UpdateDownloadStatus.downloading,
      version: 'v1.4.0',
      received: 10,
      total: 100,
    );
    return _running.future;
  }

  @override
  Future<void> pause() async {
    pauses++;
    state.value = const UpdateDownloadState(
      status: UpdateDownloadStatus.paused,
      version: 'v1.4.0',
    );
  }
}

void main() {
  late _Service service;

  setUp(() {
    Get.testMode = true;
    service = _Service();
  });

  tearDown(() {
    service.onClose();
    Get.reset();
  });

  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(
      GetMaterialApp(
        home: Scaffold(body: UpdateDownloadPanel(service: service)),
      ),
    );
    await tester.pump();
  }

  testWidgets('重新下载开始之后取消下载仍然可用', (tester) async {
    service.state.value = const UpdateDownloadState(
      status: UpdateDownloadStatus.paused,
      version: 'v1.4.0',
    );
    await mount(tester);
    expect(find.text('重新下载'), findsOneWidget);

    await tester.tap(find.text('重新下载'));
    await tester.pump();

    // 下载在服务里跑着, 面板不能把自己锁住: 取消下载被禁用的话, 用户只能
    // 等这一整包下完, 中途想停也停不下来.
    final cancel = tester.widget<TextButton>(
      find.widgetWithText(TextButton, '取消下载'),
    );
    expect(cancel.onPressed, isNotNull);

    await tester.tap(find.text('取消下载'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(service.pauses, 1);
    expect(find.text('重新下载'), findsOneWidget);
  });
}
