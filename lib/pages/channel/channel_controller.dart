import 'package:tucao/http/video_http.dart';
import 'package:tucao/common/controller/paging_controller.dart';
import 'package:tucao/models/video.dart';

/// 分区视频列表控制器.
///
/// 分区页与首页的 "更多" 入口共用.
class ChannelController extends PagingController<VideoModel> {
  ChannelController({required this.typeId, String? order})
    : order = order ?? 'date';

  final int typeId;
  String order;

  @override
  int get pageSize => 20;

  @override
  Future<List<VideoModel>> fetchPage(int page) async {
    final response = await VideoHttp.list(
      typeId: typeId,
      page: page,
      pageSize: pageSize,
      order: order,
    );
    if (!response.success) {
      throw Exception(response.message ?? '接口返回异常');
    }
    total.value = response.total;
    return response.list;
  }

  /// 切换排序方式.
  Future<void> changeOrder(String? value) async {
    if (value == null || value == order) {
      return;
    }
    order = value;
    await reload();
  }
}
