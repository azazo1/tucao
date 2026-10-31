import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tucao/common/adaptive.dart';
import 'package:tucao/common/style.dart';

/// 横屏与平板适配的断点测试.
///
/// 这里固定几件容易回退的行为: 网格不再写死两列, 矮屏下按可用高度追加
/// 列数, 首页主标签只在横屏矮屏竖到左边, 以及播放页只在屏够宽或处于
/// 横屏时左右分栏.
void main() {
  group('竖版卡片网格列数', () {
    test('手机竖屏保持两列', () {
      expect(Style.gridColumns(320), 2);
      expect(Style.gridColumns(360), 2);
      expect(Style.gridColumns(411), 2);
    });

    test('横屏与平板按宽度增加列数', () {
      expect(Style.gridColumns(640), 3);
      expect(Style.gridColumns(800), 4);
      expect(Style.gridColumns(1024), 5);
    });

    test('超宽屏不超过上限', () {
      expect(Style.gridColumns(2000), Style.maxGridColumns);
    });
  });

  group('按可用高度追加列数', () {
    testWidgets('放不下一张卡片时加列, 不传高度时只跟宽度走', (tester) async {
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (value) {
              context = value;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      const width = 635.0;
      const height = 192.0;
      final base = Style.gridColumns(width);
      final columns = Style.gridColumnsForHeight(
        context,
        width,
        availableHeight: height,
      );
      expect(columns, greaterThan(base));
      expect(
        Style.verticalCardExtent(context, Style.cardWidth(width, columns)),
        lessThanOrEqualTo(height),
      );
      expect(Style.gridColumnsForHeight(context, width), base);
    });
  });

  group('首页主标签竖排', () {
    test('横屏矮屏竖到左边', () {
      expect(Adaptive.sideTabs(const Size(800, 360)), isTrue);
      expect(Adaptive.sideTabs(const Size(640, 360)), isTrue);
    });

    test('竖屏与高度充足的横屏保持横排标签', () {
      expect(Adaptive.sideTabs(const Size(360, 800)), isFalse);
      expect(Adaptive.sideTabs(const Size(1280, 800)), isFalse);
    });

    test('宽度撑不出侧栏时不竖排', () {
      expect(Adaptive.sideTabs(const Size(560, 320)), isFalse);
    });
  });

  group('播放页宽度', () {
    test('手机竖屏保持上下结构', () {
      expect(Adaptive.splitVideoLayout(const Size(360, 800)), isFalse);
      expect(Adaptive.splitVideoLayout(const Size(411, 891)), isFalse);
    });

    test('手机横屏左右分栏', () {
      expect(Adaptive.splitVideoLayout(const Size(800, 360)), isTrue);
    });

    test('平板竖屏左右分栏', () {
      expect(Adaptive.splitVideoLayout(const Size(840, 1280)), isTrue);
    });
  });
}
