import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tucao/models/reply.dart';
import 'package:tucao/pages/reply/reply_controller.dart';
import 'package:tucao/pages/reply/reply_page.dart';
import 'package:tucao/pages/video/widgets/video_content_tabs.dart';

void main() {
  testWidgets('点击与滑动只切下方, 评论延迟加载并保留滚动和分 P 状态', (tester) async {
    final host = GlobalKey<_TabsHostState>();
    final created = <_FakeReplies>[];
    await tester.pumpWidget(
      MaterialApp(
        home: _TabsHost(key: host, created: created),
      ),
    );
    await tester.pumpAndSettle();
    final player = tester.state(find.byType(_PlayerProbe));
    expect(created, isEmpty);

    await tester.tap(find.byType(Tab).at(1));
    await tester.pumpAndSettle();
    expect(host.currentState!.tabs.index, 1);
    expect(created, hasLength(1));
    final controller = created.single;
    final list = find.descendant(
      of: find.byType(ReplyPanel),
      matching: find.byType(CustomScrollView),
    );
    await tester.drag(list, const Offset(0, -350));
    await tester.pumpAndSettle();
    final scrollable = tester.state<ScrollableState>(
      find.descendant(of: list, matching: find.byType(Scrollable)).first,
    );
    final position = scrollable.position.pixels;
    expect(position, greaterThan(0));
    controller.expanded.add(controller.list.first.id);

    await tester.drag(find.byType(TabBarView), const Offset(600, 0));
    await tester.pumpAndSettle();
    expect(host.currentState!.tabs.index, 0);
    await tester.drag(find.byType(TabBarView), const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(host.currentState!.tabs.index, 1);
    expect(identical(tester.state(find.byType(_PlayerProbe)), player), isTrue);
    expect(created, hasLength(1));
    expect(controller.firstLoads, 1);
    expect(scrollable.position.pixels, closeTo(position, 1));

    host.currentState!.changePart();
    await tester.pumpAndSettle();
    expect(created, hasLength(1));
    expect(controller.list, hasLength(60));
    expect(controller.expanded, contains(controller.list.first.id));
    expect(scrollable.position.pixels, closeTo(position, 1));
    await tester.pumpWidget(const SizedBox.shrink());
    expect(controller.isClosed, isTrue);
  });

  testWidgets('面板实例隔离, 切分区或视频关闭旧控制器', (tester) async {
    final created = <_FakeReplies>[];
    var typeId = 11;
    var hid = '123';
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return Row(
                children: [
                  Expanded(
                    child: ReplyPanel(
                      key: const ValueKey('first'),
                      typeId: typeId,
                      hid: hid,
                      controllerFactory: (typeId, hid, part) {
                        final controller = _FakeReplies(typeId, hid, part);
                        created.add(controller);
                        return controller;
                      },
                    ),
                  ),
                  Expanded(
                    child: ReplyPanel(
                      key: const ValueKey('second'),
                      typeId: 11,
                      hid: '123',
                      controllerFactory: (typeId, hid, part) {
                        final controller = _FakeReplies(typeId, hid, part);
                        created.add(controller);
                        return controller;
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(created, hasLength(2));
    expect(identical(created[0], created[1]), isFalse);
    created[0].expanded.add('0');
    expect(created[1].expanded, isEmpty);

    update(() => typeId = 24);
    await tester.pumpAndSettle();
    expect(created, hasLength(3));
    expect(created[0].isClosed, isTrue);
    expect(created[1].isClosed, isFalse);
    expect(created[2].typeId, 24);
    update(() => hid = '456');
    await tester.pumpAndSettle();
    expect(created, hasLength(4));
    expect(created[2].isClosed, isTrue);
    expect(created[3].hid, '456');
    await tester.pumpWidget(const SizedBox.shrink());
    expect(created.every((controller) => controller.isClosed), isTrue);
  });

  testWidgets('详情未就绪时选择评论不请求 typeId 0', (tester) async {
    final host = GlobalKey<_TabsHostState>();
    final created = <_FakeReplies>[];
    await tester.pumpWidget(
      MaterialApp(
        home: _TabsHost(key: host, created: created, initialTypeId: 0),
      ),
    );
    await tester.tap(find.byType(Tab).at(1));
    await tester.pumpAndSettle();
    expect(created, isEmpty);
    host.currentState!.ready();
    await tester.pumpAndSettle();
    expect(created, hasLength(1));
    expect(created.single.typeId, 11);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('窄屏大字和低高度评论区域可滚动, 键盘不挤播放器', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 300));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final host = GlobalKey<_TabsHostState>();
    final created = <_FakeReplies>[];
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(2),
            viewInsets: const EdgeInsets.only(bottom: 240),
          ),
          child: child!,
        ),
        home: _TabsHost(key: host, created: created),
      ),
    );
    await tester.tap(find.byType(Tab).at(1));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final before = tester.getRect(find.byType(_PlayerProbe));
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.getRect(find.byType(_PlayerProbe)), before);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

class _FakeReplies extends ReplyController {
  _FakeReplies(int typeId, String hid, int part)
    : super(typeId: typeId, hid: hid, part: part);

  int firstLoads = 0;

  @override
  int get pageSize => 100;

  @override
  Future<void> loadFirst() {
    firstLoads++;
    return super.loadFirst();
  }

  @override
  Future<List<ReplyModel>> fetchPage(int page) async => List.generate(
    60,
    (index) => ReplyModel(
      id: '$index',
      commentId: 'content_$typeId-$hid-1',
      userId: index + 1,
      userName: '用于测试的长用户名 $index',
      content: '用于测试滚动保留的评论内容 $index',
      createAt: '2026-10-05 12:25:05',
    ),
  );
}

class _TabsHost extends StatefulWidget {
  const _TabsHost({super.key, required this.created, this.initialTypeId = 11});

  final List<_FakeReplies> created;
  final int initialTypeId;

  @override
  State<_TabsHost> createState() => _TabsHostState();
}

class _TabsHostState extends State<_TabsHost>
    with SingleTickerProviderStateMixin {
  late final tabs = TabController(length: 2, vsync: this);
  late int typeId = widget.initialTypeId;
  int part = 0;

  void changePart() => setState(() => part++);
  void ready() => setState(() => typeId = 11);

  @override
  void dispose() {
    tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Column(
        children: [
          const SizedBox(
            width: double.infinity,
            height: 90,
            child: _PlayerProbe(),
          ),
          Expanded(
            child: VideoContentTabs(
              controller: tabs,
              typeId: typeId,
              hid: '123',
              part: part,
              introduction: ListView.builder(
                itemCount: 40,
                itemBuilder: (context, index) =>
                    SizedBox(height: 50, key: ValueKey(index)),
              ),
              replyControllerFactory: (typeId, hid, part) {
                final controller = _FakeReplies(typeId, hid, part);
                widget.created.add(controller);
                return controller;
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _PlayerProbe extends StatefulWidget {
  const _PlayerProbe();

  @override
  State<_PlayerProbe> createState() => _PlayerProbeState();
}

class _PlayerProbeState extends State<_PlayerProbe> {
  @override
  Widget build(BuildContext context) => const ColoredBox(color: Colors.black);
}
