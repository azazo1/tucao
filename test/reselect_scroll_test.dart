import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tucao/common/widgets/reselect_scroll.dart';

class _Tab extends StatefulWidget {
  const _Tab({required this.name, required this.refreshed});

  final String name;
  final List<String> refreshed;

  @override
  State<_Tab> createState() => _TabState();
}

class _TabState extends State<_Tab> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return RefreshIndicator(
      onRefresh: () async => widget.refreshed.add(widget.name),
      child: ListView.builder(
        key: ValueKey(widget.name),
        itemCount: 100,
        itemBuilder: (context, i) =>
            SizedBox(height: 80, child: Text('${widget.name} $i')),
      ),
    );
  }
}

void main() {
  testWidgets('重复点击只作用于屏幕上的分区: 先回顶部, 再刷新, 保活的离屏分区不动', (tester) async {
    final refreshed = <String>[];
    final root = GlobalKey();
    final tabs = TabController(length: 2, vsync: const TestVSync());
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: KeyedSubtree(
            key: root,
            child: TabBarView(
              controller: tabs,
              children: [
                _Tab(name: 'a', refreshed: refreshed),
                _Tab(name: 'b', refreshed: refreshed),
              ],
            ),
          ),
        ),
      ),
    );

    ScrollPosition position(String name) => tester
        .state<ScrollableState>(
          find.descendant(
            of: find.byKey(ValueKey(name), skipOffstage: false),
            matching: find.byType(Scrollable),
            skipOffstage: false,
          ),
        )
        .position;

    // 切走后保活的分区找不到了, 先把位置对象拿在手里.
    final a = position('a')..jumpTo(3000);
    tabs.index = 1;
    await tester.pumpAndSettle();
    position('b').jumpTo(500);
    await tester.pump();

    expect(
      ReselectScroll.handle(root.currentContext!),
      ReselectAction.scrolledToTop,
    );
    await tester.pumpAndSettle();
    expect(position('b').pixels, 0);
    // 离屏的 a 分区保持原来的位置.
    expect(a.pixels, 3000);

    expect(
      ReselectScroll.handle(root.currentContext!),
      ReselectAction.refreshed,
    );
    await tester.pumpAndSettle();
    expect(refreshed, ['b']);
    tabs.dispose();
  });
}
