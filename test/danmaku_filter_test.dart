import 'package:flutter_test/flutter_test.dart';
import 'package:tucao/models/danmaku.dart';
import 'package:tucao/models/danmaku_filter.dart';
import 'package:tucao/utils/danmaku_filter_migration.dart';

DanmakuModel _item(double time, String text) => DanmakuModel(
  time: time,
  mode: 1,
  fontSize: 25,
  color: 0xFFFFFF,
  timestamp: 0,
  text: text,
);

List<String> _texts(List<DanmakuModel> list) =>
    list.map((item) => '${item.time}:${item.text}').toList();

void main() {
  test('普通屏蔽词不区分大小写, 正则屏蔽词按正则匹配, 无效正则被忽略', () {
    const filter = DanmakuFilter(
      keywords: ['awsl', r'/^前方/', '/[/'],
      mergeDuplicates: false,
    );
    final result = filter.apply([
      _item(1, 'AWSL 太可爱'),
      _item(2, '前方高能'),
      _item(3, '高能前方'),
      _item(4, '  '),
    ]);
    expect(_texts(result), ['3.0:高能前方']);
  });

  test('窗口内重复合并到第一条, 超过窗口重新计数, 达到阈值才标注条数', () {
    const filter = DanmakuFilter();
    final result = filter.apply([
      _item(0, '哈哈'),
      _item(1, '哈哈 '),
      _item(2, '233'),
      _item(3, '哈哈'),
      _item(5, '233'),
      // 距第一条 "哈哈" 超过 10 秒, 另起一组.
      _item(11, '哈哈'),
    ]);
    expect(_texts(result), ['0.0:哈哈 ×3', '2.0:233', '11.0:哈哈']);
  });

  test('迁移只接受当前版本, 屏蔽词规整去重', () {
    expect(DanmakuFilterMigration.migrate({'version': 99}), isNull);
    expect(DanmakuFilterMigration.migrate('bad'), isNull);
    final filter = DanmakuFilterMigration.migrate({
      'version': DanmakuFilter.version,
      'keywords': [' a ', 'a', '', 3, 'b'],
      'mergeDuplicates': false,
    });
    expect(filter?.keywords, ['a', 'b']);
    expect(filter?.mergeDuplicates, isFalse);
  });
}
