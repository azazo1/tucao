/// 番组信息的一项.
///
/// 标签与值都来自站点播放页的 `.vdata_info .b` 区块, 不同条目的字段
/// 不完全相同, 因此不写死字段名, 只保留页面给出的顺序.
class SubjectField {
  const SubjectField({required this.label, required this.value});

  final String label;
  final String value;
}

/// 站点播放页里的番组信息.
class VideoSubjectInfo {
  const VideoSubjectInfo(this.fields);

  static const empty = VideoSubjectInfo([]);

  final List<SubjectField> fields;

  bool get isEmpty => fields.isEmpty;

  bool get isNotEmpty => fields.isNotEmpty;

  /// 按标签取值, 找不到时返回空串.
  String valueOf(String label) {
    for (final field in fields) {
      if (field.label == label) {
        return field.value;
      }
    }
    return '';
  }
}

/// 播放页 html 里能解析出的附加信息.
class VideoPlayPageDetail {
  const VideoPlayPageDetail({required this.description, required this.subject});

  final String description;
  final VideoSubjectInfo subject;
}
