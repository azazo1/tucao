import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:tucao/models/download_task.dart';
import 'package:tucao/models/video.dart';
import 'package:tucao/pages/download/download_page.dart';
import 'package:tucao/pages/video/widgets/download_sheet.dart';
import 'package:tucao/services/download/download_service.dart';

class _LayoutDownloads extends GetxController implements DownloadService {
  @override
  final ready = true.obs;
  @override
  final initializationError = RxnString();
  @override
  final items = <DownloadTask>[
    const DownloadTask(hid: '123', part: 0,
      title: '很长的视频标题用于检查小屏幕中列表的文字和操作按钮是否仍能使用',
      partTitle: '很长的分集名称同样需要换行显示而不挤出操作按钮',
      source: 'https://media.invalid/movie.mp4', createdAt: 1,
      status: DownloadStatus.paused),
  ].obs;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(() {
    Get.testMode = true;
    Get.put<DownloadService>(_LayoutDownloads());
  });
  tearDown(Get.reset);

  Future<void> viewport(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Widget app(Widget child) => GetMaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.5)),
      child: child!,
    ),
    home: child,
  );

  testWidgets('小屏缓存列表的大字号与长标题不会挤出操作区', (tester) async {
    await viewport(tester, const Size(320, 568));
    await tester.pumpWidget(app(const DownloadPage()));
    await tester.pump();
    expect(tester.takeException(), isNull);
    final remove = find.byKey(const ValueKey('download-remove-123-0'));
    expect(remove, findsOneWidget);
    expect(tester.getRect(remove).right, lessThanOrEqualTo(320));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('横向小屏分P选择的大字号布局不溢出', (tester) async {
    await viewport(tester, const Size(568, 240));
    const video = VideoModel(hid: '123', title: '测试', parts: [
      VideoPart(title: '测试分集', file: 'https://media.invalid/movie.mp4'),
    ]);
    await tester.pumpWidget(app(Scaffold(body: Builder(builder: (context) => IconButton(
      icon: const Icon(Icons.download),
      onPressed: () => showVideoDownloadSheet(context, video: video, initialPart: 0),
    )))));
    await tester.tap(find.byIcon(Icons.download));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final submit = find.byKey(const ValueKey('download-submit'));
    expect(submit, findsOneWidget);
    expect(tester.getRect(submit).bottom, lessThanOrEqualTo(240));
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
