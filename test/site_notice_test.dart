import 'package:flutter_test/flutter_test.dart';
import 'package:tucao/common/constants.dart';
import 'package:tucao/http/site_notice_http.dart';

void main() {
  test('轮转区只取站务文章, 去重并补全图片地址', () {
    const raw = '''
<div class="focus">
  <div class="slide"><a href="/play/d7241/" class="i"><img src="/uploadfile/a.jpg"></a><a href="/play/d7241/" class="t"><div>【倒计时30天】破会员</div><p>做任务</p></a></div>
  <div class="slide"><a href="/play/h4107879/" class="i"><img src="https://www.tucao.my/b.jpg"></a><a href="/play/h4107879/" class="t"><div>【10月】新番</div><p>简介</p></a></div>
  <div class="slide"><a href="/play/d7320/" class="i"><img src="https://img.example/c.jpg"></a><a href="/play/d7320/" class="t"><div>app 版</div></a></div>
  <div class="slide"><a href="/play/d7241/" class="i"></a><a href="/play/d7241/" class="t"><div>重复</div></a></div>
</div>
<div class="list"><div class="slide"><a href="/play/d1/" class="t"><div>轮转区外</div></a></div></div>
''';
    final list = SiteNoticeHttp.parseHomeHtml(raw);
    expect(list.map((item) => item.hid), ['7241', '7320']);
    expect(list[0].cover, '${Constants.baseUrl}uploadfile/a.jpg');
    expect(list[0].summary, '做任务');
    expect(list[1].summary, isEmpty);
    expect(list[1].cover, 'https://img.example/c.jpg');
  });
}
