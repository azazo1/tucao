import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tucao/common/adaptive.dart';
import 'package:tucao/common/style.dart';

/// 横屏与平板适配的断点测试.
///
/// 这里固定两件容易回退的行为: 网格不再写死两列,
/// 以及播放页只在屏够宽或处于横屏时左右分栏.
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
