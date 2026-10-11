import 'package:flutter_test/flutter_test.dart';
import 'package:tucao/common/controller/paging_controller.dart';

/// 分页判断逻辑的测试.
///
/// 站点列表接口的 total_count 返回的是本页条数而不是总数
/// (pagesize=2 时为 2, pagesize=5 时为 5, 末页为 0), 拿它当总数会让
/// hasMore 在第一页就变成 false, 因此是否还有下一页按本页条数判断.
class _FakePaging extends PagingController<int> {
  _FakePaging(this.pages);

  /// 每一页返回的数据, 超出范围视为空页. 测试中可以改动它模拟站点数据变化.
  final List<List<int>> pages;

  final requested = <int>[];

  int _size = 3;

  @override
  int get pageSize => _size;

  set pageSizeOverride(int value) => _size = value;

  @override
  Future<List<int>> fetchPage(int page) async {
    requested.add(page);
    final index = page - 1;
    if (index < 0 || index >= pages.length) {
      return const [];
    }
    return pages[index];
  }
}

void main() {
  group('分页判断', () {
    test('取满一页时还有下一页', () async {
      final controller = _FakePaging([
        [1, 2, 3],
        [4, 5, 6],
      ]);
      await controller.loadFirst();
      expect(controller.list, [1, 2, 3]);
      expect(controller.hasMore, isTrue);
    });

    test('未取满一页时没有下一页', () async {
      final controller = _FakePaging([
        [1, 2],
      ]);
      await controller.loadFirst();
      expect(controller.hasMore, isFalse);
    });

    test('可以连续翻到最后一页', () async {
      final controller = _FakePaging([
        [1, 2, 3],
        [4, 5, 6],
        [7],
      ]);
      await controller.loadFirst();
      await controller.loadMore();
      expect(controller.list, [1, 2, 3, 4, 5, 6]);
      expect(controller.hasMore, isTrue);

      await controller.loadMore();
      expect(controller.list, [1, 2, 3, 4, 5, 6, 7]);
      expect(controller.hasMore, isFalse);
      expect(controller.requested, [1, 2, 3]);
    });

    test('到底后不再请求', () async {
      final controller = _FakePaging([
        [1],
      ]);
      await controller.loadFirst();
      await controller.loadMore();
      await controller.loadMore();
      expect(controller.requested, [1]);
    });

    test('空页视为到底', () async {
      final controller = _FakePaging([<int>[]]);
      await controller.loadFirst();
      expect(controller.hasMore, isFalse);
      expect(controller.list, isEmpty);
    });

    test('刷新会重置到底状态', () async {
      final controller = _FakePaging([
        [1],
        [1, 2, 3],
      ]);
      await controller.loadFirst();
      expect(controller.hasMore, isFalse);
      // 站点数据变了, 第一页重新取满, 刷新后应当重新认为还有下一页.
      controller.pages[0] = [1, 2, 3];
      await controller.refresh();
      expect(controller.list, [1, 2, 3]);
      expect(controller.hasMore, isTrue);
    });

    test('站点返回的 total 不影响分页判断', () async {
      final controller = _FakePaging([
        [1, 2, 3],
      ]);
      await controller.loadFirst();
      // total_count 语义不可靠, 即使它是 0 也不应影响翻页.
      controller.total.value = 0;
      expect(controller.hasMore, isTrue);
    });
  });
}
