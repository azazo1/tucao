import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tucao/common/widgets/cover_hero.dart';

/// 同一视频的两张卡片, 只有被点的那张带 tag, 推入和返回都不会撞 tag.
Widget _card(String label) => HeroLaunch(
  hid: 'same',
  builder: (context, tag, launch) => GestureDetector(
    onTap: () {
      final heroTag = launch();
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            body: CoverHero.wrap(
              tag: heroTag,
              child: const SizedBox(width: 300, height: 200),
            ),
          ),
        ),
      );
    },
    child: CoverHero.wrap(
      tag: tag,
      child: SizedBox(width: 100, height: 60, child: Text(label)),
    ),
  ),
);

void main() {
  testWidgets('同一视频出现两次时点击只让被点的封面飞, 来回都不报重复 tag', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: Column(children: [_card('a'), _card('b')])),
      ),
    );
    expect(find.byType(Hero), findsNothing);

    await tester.tap(find.text('b'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    // 飞行途中画的是来源封面.
    expect(find.text('b'), findsWidgets);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    Navigator.of(tester.element(find.byType(SizedBox).last)).pop();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // 再点另一张, 旧 tag 还挂在第一张上也不冲突.
    await tester.tap(find.text('a'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
