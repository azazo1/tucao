import 'package:flutter_test/flutter_test.dart';
import 'package:tucao/services/account_service.dart';

/// 注册响应判定的测试.
///
/// 站点成功时返回的页面正文是 "操作成功" 加一段跳转脚本,
/// 失败时把提示放在 script 里. 这里只验证纯函数判定, 不发起请求.
void main() {
  group('注册响应判定', () {
    test('成功响应视为无错误', () {
      const raw =
          '<body>操作成功 '
          'setTimeout("redirect(\'index.php?m=member&c=index&a=init\');",1250);'
          '</body>';
      expect(AccountService.registerFailure(raw), isNull);
    });

    test('脚本里的提示文案被提取', () {
      const raw = "<script>showmessage('用户名已存在', 'back');</script>";
      expect(AccountService.registerFailure(raw), '用户名已存在');
    });

    test('无提示文案时按关键字兜底', () {
      const raw = '<body>该邮箱已经被注册</body>';
      expect(AccountService.registerFailure(raw), '注册失败, 请检查填写的信息');
    });

    test('空响应与未知页面不能作为注册成功依据', () {
      for (final raw in [
        '',
        '<body>服务暂不可用</body>',
        '<body><form><input name="username"></form>操作成功</body>',
        '<script>var message = "操作成功";</script>',
        '<style>.操作成功 { color: red; }</style>',
      ]) {
        expect(AccountService.registerFailure(raw), isNotNull);
      }
    });
  });

  group('修改密码响应判定', () {
    test('会话过期时给出提示而不是静默成功', () {
      // 站点未登录时返回的正文是 "您的会话已过期, 请重新登录.".
      const raw =
          '<body>您的会话已过期，请重新登录。 '
          'setTimeout("redirect(\'index.php?m=member&amp;c=index&amp;a=login\');",1250);'
          '</body>';
      final failure = AccountService.formFailure(
        raw,
        fallback: '修改密码失败, 请检查填写的信息',
      );
      expect(failure, isNotNull);
    });

    test('成功响应视为无错误', () {
      const raw =
          '<body>操作成功 '
          'setTimeout("redirect(\'index.php?m=member&amp;c=index\');",1250);'
          '</body>';
      expect(AccountService.formFailure(raw, fallback: '修改密码失败'), isNull);
    });

    test('成功标记与拒绝提示同时出现时不能判为成功', () {
      for (final raw in [
        '<body>操作成功失败</body>',
        '<body>操作成功<script>showmessage(\'原密码不正确\', \'back\');</script></body>',
      ]) {
        expect(
          AccountService.formFailure(raw, fallback: 'rejected'),
          isNotNull,
        );
      }
    });

    test('旧密码错误时提取站点文案', () {
      const raw = "<script>showmessage('原密码不正确', 'back');</script>";
      expect(AccountService.formFailure(raw, fallback: '修改密码失败'), '原密码不正确');
    });
  });
}
