import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:tucao/models/reply.dart';
import 'package:tucao/pages/reply/reply_controller.dart';
import 'package:tucao/pages/reply/reply_page.dart' show ReplyPanel;
import 'package:tucao/pages/reply/widgets/comment_tile.dart';

/// 评论楼中楼的展开, 分页与失败重试.
///
/// 这里覆盖一次真实出现过的问题: 回复写回列表模型后, 列表项重建时
/// 仍持有旧对象, 展开后一条回复也显示不出来.
class _FakeReplyController extends ReplyController {
  _FakeReplyController({this.roots = const [], this.pages = const {}})
    : super(typeId: 11, hid: '4107869');

  final List<ReplyModel> roots;
  final Map<int, List<ReplyModel>> pages;
  final requestedPages = <int>[];

  /// 不为空时 [fetchReplies] 抛出该异常.
  Object? failure;

  @override
  Future<List<ReplyModel>> fetchPage(int page) async => roots;

  @override
  Future<ReplyPage> fetchReplies(int replyId, int page) async {
    requestedPages.add(page);
    final error = failure;
    if (error != null) {
      throw error;
    }
    return ReplyPage(total: 0, list: pages[page] ?? const []);
  }
}

ReplyModel _reply(
  String id, {
  String content = '内容',
  int replyCount = 0,
  int replyId = 1,
}) {
  return ReplyModel(
    id: id,
    commentId: 'content_11-4107869-1',
    userId: 1,
    userName: '用户$id',
    content: content,
    replyId: replyId,
    replyCount: replyCount,
  );
}

Future<_FakeReplyController> _startController(
  _FakeReplyController controller,
) async {
  controller.onStart();
  await Future<void>.delayed(Duration.zero);
  return controller;
}

Widget _panel(_FakeReplyController controller) {
  return GetMaterialApp(
    home: Scaffold(
      body: ReplyPanel(
        typeId: 11,
        hid: '4107869',
        controllerFactory: (typeId, hid, part) => controller,
      ),
    ),
  );
}

void main() {
  group('楼中楼状态', () {
    test('加载结果放在独立状态里, 不写回评论模型', () async {
      final root = _reply('1', replyCount: 1);
      final controller = await _startController(
        _FakeReplyController(
          roots: [root],
          pages: {
            1: [_reply('2', replyId: 1)],
          },
        ),
      );

      await controller.loadReplies(root);

      expect(controller.expanded.contains('1'), isTrue);
      expect(controller.threadOf('1').items.map((item) => item.id), ['2']);
      expect(controller.list.first.replies, isEmpty);
      expect(controller.replyCount(root), 1);
    });

    test('按页追加, 取不满一页后不再请求', () async {
      final root = _reply('1', replyCount: 25);
      final controller = await _startController(
        _FakeReplyController(
          pages: {
            1: List.generate(20, (index) => _reply('a$index')),
            2: List.generate(5, (index) => _reply('b$index')),
          },
        ),
      );

      await controller.loadReplies(root);
      expect(controller.threadOf('1').items, hasLength(20));
      expect(controller.hasMoreReplies(root), isTrue);

      await controller.loadMoreReplies(root);
      expect(controller.threadOf('1').items, hasLength(25));
      expect(controller.threadOf('1').exhausted, isTrue);
      expect(controller.hasMoreReplies(root), isFalse);

      await controller.loadMoreReplies(root);
      expect(controller.requestedPages, [1, 2]);
    });

    test('首屏失败记录错误, 重试后展开', () async {
      final root = _reply('1', replyCount: 1);
      final controller = await _startController(
        _FakeReplyController(
          pages: {
            1: [_reply('2', replyId: 1)],
          },
        ),
      );
      controller.failure = Exception('网络错误');

      await expectLater(controller.loadReplies(root), throwsException);
      expect(controller.threadOf('1').error, isNotNull);
      expect(controller.threadOf('1').loading, isFalse);
      expect(controller.expanded.contains('1'), isFalse);

      controller.failure = null;
      await controller.retryReplies(root);
      expect(controller.threadOf('1').items, hasLength(1));
      expect(controller.expanded.contains('1'), isTrue);
    });

    test('后续页失败后重试同一页', () async {
      final root = _reply('1', replyCount: 25);
      final controller = await _startController(
        _FakeReplyController(
          pages: {
            1: List.generate(20, (index) => _reply('a$index')),
            2: List.generate(5, (index) => _reply('b$index')),
          },
        ),
      );
      await controller.loadReplies(root);
      controller.failure = Exception('网络错误');

      await expectLater(controller.loadMoreReplies(root), throwsException);
      expect(controller.threadOf('1').failedPage, 2);
      expect(controller.threadOf('1').items, hasLength(20));

      controller.failure = null;
      await controller.retryReplies(root);
      expect(controller.requestedPages, [1, 2, 2]);
      expect(controller.threadOf('1').items, hasLength(25));
    });
  });

  group('楼中楼交互', () {
    testWidgets('点击入口展开回复, 点击收起后恢复入口', (tester) async {
      final controller = _FakeReplyController(
        roots: [_reply('1', replyCount: 2)],
        pages: {
          1: [_reply('2', replyId: 1), _reply('3', replyId: 1)],
        },
      );

      await tester.pumpWidget(_panel(controller));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 10));
      expect(find.byType(CommentTile), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('reply-toggle-1')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 10));

      expect(find.byKey(const ValueKey('reply-thread-1')), findsOneWidget);
      expect(find.byType(CommentTile), findsNWidgets(3));

      await tester.tap(find.byKey(const ValueKey('reply-collapse-1')));
      await tester.pump();

      expect(find.byKey(const ValueKey('reply-thread-1')), findsNothing);
      expect(find.byKey(const ValueKey('reply-toggle-1')), findsOneWidget);
      expect(find.byType(CommentTile), findsOneWidget);
    });
  });
}
