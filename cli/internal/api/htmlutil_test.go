package api

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// fixturePath 指向仓库根目录下的页面样本.
//
// 样本由安卓端的解析测试与本次实现共用, 因此测试必须在仓库内运行.
func fixturePath(name string) string {
	return filepath.Join("..", "..", "..", "test", "fixtures", name)
}

func readFixture(t *testing.T, name string) string {
	t.Helper()
	data, err := os.ReadFile(fixturePath(name))
	if err != nil {
		t.Fatalf("读取样本 %s 失败: %v", name, err)
	}
	return string(data)
}

func TestDecodeHTMLText(t *testing.T) {
	cases := []struct {
		name string
		raw  string
		want string
	}{
		{name: "实体解码", raw: "名校&mdash;&mdash;藤成学园", want: "名校——藤成学园"},
		{name: "换行转换", raw: "第一行<br>第二行", want: "第一行\n第二行"},
		{name: "自闭合换行", raw: "第一行<br/>第二行", want: "第一行\n第二行"},
		{name: "二次转义", raw: "&amp;acute;", want: "´"},
		{name: "去标签", raw: "<b>加粗</b>正文", want: "加粗正文"},
		{name: "空串", raw: "", want: ""},
	}
	for _, testCase := range cases {
		t.Run(testCase.name, func(t *testing.T) {
			if got := decodeHTMLText(testCase.raw); got != testCase.want {
				t.Fatalf("decodeHTMLText(%q) = %q, 期望 %q", testCase.raw, got, testCase.want)
			}
		})
	}
}

func TestDecodeHTMLTextOnRealDescription(t *testing.T) {
	raw := readFixture(t, "view.json")
	if !strings.Contains(raw, "&mdash;") {
		t.Skip("样本里没有带实体的简介")
	}
	if got := decodeHTMLText("这里是位于城郊的升学名校&mdash;&mdash;私立藤成学园。"); !strings.Contains(got, "——") {
		t.Fatalf("真实简介里的实体没有解开: %q", got)
	}
}

func TestBackgroundURL(t *testing.T) {
	cases := []struct {
		raw  string
		want string
	}{
		{raw: `background-image:url(https://a/b.jpg)`, want: "https://a/b.jpg"},
		{raw: `background-image:url('https://a/b.jpg')`, want: "https://a/b.jpg"},
		{raw: `background-image: url("https://a/b.jpg")`, want: "https://a/b.jpg"},
		{raw: `background: #fff`, want: ""},
		{raw: "", want: ""},
	}
	for _, testCase := range cases {
		if got := backgroundURL(testCase.raw); got != testCase.want {
			t.Fatalf("backgroundURL(%q) = %q, 期望 %q", testCase.raw, got, testCase.want)
		}
	}
}

func TestFirstCount(t *testing.T) {
	cases := []struct {
		raw  string
		want int
	}{
		{raw: "1.2万次播放", want: 12000},
		{raw: "3亿次播放", want: 300000000},
		{raw: "44,489次播放", want: 44489},
		{raw: "暂无播放", want: 0},
		{raw: "", want: 0},
	}
	for _, testCase := range cases {
		if got := firstCount(testCase.raw); got != testCase.want {
			t.Fatalf("firstCount(%q) = %d, 期望 %d", testCase.raw, got, testCase.want)
		}
	}
}

func TestAbsoluteURL(t *testing.T) {
	base := "https://www.tucao.my/"
	cases := []struct {
		raw  string
		want string
	}{
		{raw: "statics/a.png", want: "https://www.tucao.my/statics/a.png"},
		{raw: "/statics/a.png", want: "https://www.tucao.my/statics/a.png"},
		{raw: "https://cdn/a.png", want: "https://cdn/a.png"},
		{raw: "", want: ""},
	}
	for _, testCase := range cases {
		if got := absoluteURL(base, testCase.raw); got != testCase.want {
			t.Fatalf("absoluteURL(%q) = %q, 期望 %q", testCase.raw, got, testCase.want)
		}
	}
}

func TestHrefExtraction(t *testing.T) {
	if got := hrefHID("https://www.tucao.my/play/h4107864/#2"); got != "4107864" {
		t.Fatalf("hrefHID = %q", got)
	}
	if got := hrefHID("/play/4107864/"); got != "4107864" {
		t.Fatalf("hrefHID 兼容旧写法失败: %q", got)
	}
	if got := hrefUID("/play/u442223/"); got != 442223 {
		t.Fatalf("hrefUID = %d", got)
	}
	if got := hrefUID(""); got != 0 {
		t.Fatalf("hrefUID 空值应为 0, 实际 %d", got)
	}
}

func TestParseStatsScript(t *testing.T) {
	raw := `$('#olThis').html('123');$('#olAll').html('4,567');$('#hits').html('89');`
	values := ParseStatsScript(raw)
	if values["olThis"] != "123" || values["olAll"] != "4,567" || values["hits"] != "89" {
		t.Fatalf("统计脚本解析结果不正确: %v", values)
	}
	if got := numberOrNil(values["olAll"]); got == nil || *got != 4567 {
		t.Fatalf("带千分位的统计没有解析成数字: %v", got)
	}
	if got := numberOrNil("暂无"); got != nil {
		t.Fatalf("无法解析的统计应为空, 实际 %v", *got)
	}
}
