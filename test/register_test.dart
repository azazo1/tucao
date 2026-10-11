import 'package:flutter_test/flutter_test.dart';
import 'package:tucao/services/account_service.dart';

/// 注册响应判定的测试.
///
/// 站点成功时返回的页面正文是 "操作成功" 加一段跳转脚本,
/// 失败时把提示放在 script 里. 这里只验证纯函数判定, 不发起请求.
void main() {
  group('注册响应判定', () {
    test('成功响应视为无错误', () {
      const raw = '<body>操作成功 '
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

    test('空响应不误报为失败', () {
      expect(AccountService.registerFailure(''), isNull);
    });
  });
}
