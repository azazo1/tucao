import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tucao/common/widgets/stats_bar.dart';

void main() {
  Future<void> pumpBar(WidgetTester tester, {required bool busy}) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatsBar(
            items: [
              const StatsBarItem(
                icon: Icons.play_circle_outline,
                label: '播放',
                value: 12,
              ),
              StatsBarItem(
                icon: Icons.favorite_border,
                label: '追番',
                value: 6,
                onTap: () {},
                busy: busy,
              ),
            ],
          ),
        ),
      ),
    );
  }

  testWidgets('追番项在提交中不改变统计条高度', (tester) async {
    await pumpBar(tester, busy: false);
    final height = tester.getSize(find.byType(StatsBar)).height;
    expect(height, greaterThan(0));
    expect(find.byType(CircularProgressIndicator), findsNothing);

    // 提交中把图标换成转圈, 高度必须与平时一致, 否则整条统计条会跟着跳.
    await pumpBar(tester, busy: true);
    expect(tester.getSize(find.byType(StatsBar)).height, height);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await pumpBar(tester, busy: false);
    expect(tester.getSize(find.byType(StatsBar)).height, height);
  });
}
