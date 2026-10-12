import 'package:html/parser.dart' as html_parser;

enum FormResponseStatus { success, rejected, unknown }

/// 站点表单返回的提示页, 未识别的页面不能作为成功依据.
class FormResponse {
  const FormResponse(this.status, this.message);

  final FormResponseStatus status;
  final String message;

  bool get isSuccess => status == FormResponseStatus.success;

  /// 成功标记只从正文读取, 不执行或采信脚本里的内容.
  factory FormResponse.parse(String raw) {
    final document = html_parser.parse(raw);
    for (final node in document.querySelectorAll('script, style, noscript')) {
      node.remove();
    }
    final body = document.body;
    final text = (body?.text ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.isEmpty ||
        body == null ||
        body.querySelector('form, input') != null ||
        text.length > 500) {
      return const FormResponse(FormResponseStatus.unknown, '站点返回了未识别的响应, 请稍后重试');
    }
    if (RegExp(r'错误|失败|不正确|不存在|不能为空|过期|不成功|未成功|不允许').hasMatch(text)) {
      return FormResponse(FormResponseStatus.rejected, text);
    }
    if (text.contains('成功')) {
      return FormResponse(FormResponseStatus.success, text);
    }
    // 实测失败页通过 history.back() 返回表单, 提示不限于固定错误关键词.
    if (body.querySelector('a[href^="javascript:history.back"]') != null) {
      return FormResponse(FormResponseStatus.rejected, text);
    }
    return const FormResponse(FormResponseStatus.unknown, '站点返回了未识别的响应, 请稍后重试');
  }
}
