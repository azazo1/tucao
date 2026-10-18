import 'package:tucao/common/constants.dart';

/// 站点评论表情, 与评论输入框里的表情面板一致.
class ReplySmile {
  const ReplySmile({required this.code, required this.path});

  /// 插入输入框的文本, 形如 `[滑稽]`.
  final String code;

  /// 相对于站点根目录的图片地址.
  final String path;

  String get url => '${Constants.baseUrl}$path';
}

const replySmiles = <ReplySmile>[
  ReplySmile(code: '[发呆]', path: 'statics/images/smilies/发呆.gif'),
  ReplySmile(code: '[滑稽]', path: 'statics/images/smilies/滑稽.gif'),
  ReplySmile(code: '[愤怒]', path: 'statics/images/smilies/愤怒.gif'),
  ReplySmile(code: '[流泪]', path: 'statics/images/smilies/流泪.gif'),
  ReplySmile(code: '[色]', path: 'statics/images/smilies/色.gif'),
  ReplySmile(code: '[晕]', path: 'statics/images/smilies/晕.gif'),
  ReplySmile(code: '[眨眼]', path: 'statics/images/smilies/眨眼.gif'),
  ReplySmile(code: '[亲亲]', path: 'statics/images/smilies/亲亲.gif'),
  ReplySmile(code: '[难受]', path: 'statics/images/smilies/难受.gif'),
];
