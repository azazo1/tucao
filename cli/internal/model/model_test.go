package model

import "testing"

func TestNormalizeHost(t *testing.T) {
	cases := []struct {
		raw  string
		want string
		ok   bool
	}{
		{raw: "www.tucao.my", want: "www.tucao.my", ok: true},
		{raw: "https://www.tucao.my/", want: "www.tucao.my", ok: true},
		{raw: "WWW.TUCAO.MY", want: "www.tucao.my", ok: true},
		{raw: "  http://www.tucao.my/play/h1/  ", want: "www.tucao.my", ok: true},
		{raw: "www.tucao.my:8443", want: "www.tucao.my:8443", ok: true},
		{raw: "www.tucao.my:0", ok: false},
		{raw: "www.tucao.my:70000", ok: false},
		{raw: "www.tucao.my:abc", ok: false},
		{raw: "localhost", ok: false},
		{raw: "tucao", ok: false},
		{raw: "", ok: false},
		{raw: "www..my", ok: false},
		{raw: "-www.tucao.my", ok: false},
	}
	for _, testCase := range cases {
		got, ok := NormalizeHost(testCase.raw)
		if ok != testCase.ok {
			t.Fatalf("NormalizeHost(%q) 合法性为 %v, 期望 %v", testCase.raw, ok, testCase.ok)
		}
		if ok && got != testCase.want {
			t.Fatalf("NormalizeHost(%q) = %q, 期望 %q", testCase.raw, got, testCase.want)
		}
	}
}

func TestCompareVersions(t *testing.T) {
	cases := []struct {
		left, right string
		want        int
	}{
		{left: "1.2.0", right: "1.1.9", want: 1},
		{left: "v1.2.0", right: "1.2.0", want: 0},
		{left: "1.2", right: "1.2.0", want: 0},
		{left: "1.2.0", right: "1.2.1", want: -1},
		{left: "v2.0.0-a1b2c3d", right: "2.0.0", want: 0},
		{left: "cli-v0.1.0", right: "1.3.0", want: -1},
		{left: "devel", right: "1.0.0", want: -1},
	}
	for _, testCase := range cases {
		got := CompareVersions(testCase.left, testCase.right)
		switch {
		case testCase.want > 0 && got <= 0:
			t.Fatalf("CompareVersions(%q, %q) = %d, 期望正数", testCase.left, testCase.right, got)
		case testCase.want < 0 && got >= 0:
			t.Fatalf("CompareVersions(%q, %q) = %d, 期望负数", testCase.left, testCase.right, got)
		case testCase.want == 0 && got != 0:
			t.Fatalf("CompareVersions(%q, %q) = %d, 期望 0", testCase.left, testCase.right, got)
		}
	}
	if !IsNewer("1.3.0", "v1.4.0") {
		t.Fatal("1.4.0 应比 1.3.0 新")
	}
	if IsNewer("1.3.0", "1.3.0") {
		t.Fatal("同版本不应判为新")
	}
}

func TestApplyPlayPartsFillsTruncatedLinks(t *testing.T) {
	video := Video{
		PartCount: 2,
		Parts: []VideoPart{
			{Index: 0, Number: 1, Title: "第一话", File: "https://x/download.aspx?share"},
			{Index: 1, Number: 2, Title: "第二话", File: "https://x/download.aspx?share"},
		},
	}
	video.ApplyPlayParts([]PlayPagePart{
		{Type: "video", File: "https://x/download.aspx?share=AAA"},
		{Type: "video", File: "https://x/download.aspx?share=BBB"},
		{Type: "video", File: "https://x/download.aspx?share=CCC"},
	})
	if video.Parts[0].File != "https://x/download.aspx?share=AAA" {
		t.Fatalf("首P地址没有补全: %q", video.Parts[0].File)
	}
	if video.Parts[1].File != "https://x/download.aspx?share=BBB" {
		t.Fatalf("第二P地址没有补全: %q", video.Parts[1].File)
	}
	// 标题仍取详情接口的, 多出来的播放页条目要被忽略.
	if video.Parts[0].Title != "第一话" {
		t.Fatalf("标题被改写: %q", video.Parts[0].Title)
	}
	if len(video.Parts) != 2 || video.PartCount != 2 {
		t.Fatalf("多余条目变成了幽灵分P: %d %d", len(video.Parts), video.PartCount)
	}
}

func TestApplyPlayPartsBuildsPartsWhenAPIHasNone(t *testing.T) {
	video := Video{}
	video.ApplyPlayParts([]PlayPagePart{
		{Type: "video", File: "https://x/1.mp4"},
		{Type: "video", File: "https://x/2.mp4"},
	})
	if len(video.Parts) != 2 || video.PartCount != 2 {
		t.Fatalf("接口没有分P时应用播放页建立列表: %+v", video.Parts)
	}
	if video.Parts[1].Number != 2 || video.Parts[1].Title != "p2" {
		t.Fatalf("生成的分P信息不正确: %+v", video.Parts[1])
	}
}

func TestApplyPlayPartsKeepsThirdPartyFlag(t *testing.T) {
	video := Video{Parts: []VideoPart{{Index: 0, Number: 1, ThirdParty: true, VID: "abc"}}}
	// 播放页没有地址时不改动.
	video.ApplyPlayParts(nil)
	if !video.Parts[0].ThirdParty {
		t.Fatal("没有播放页地址时不应改动分P")
	}
	// 地址没变时也不改动类型标记.
	video.Parts[0].File = "https://x/1.mp4"
	video.ApplyPlayParts([]PlayPagePart{{Type: "video", File: "https://x/1.mp4"}})
	if !video.Parts[0].ThirdParty {
		t.Fatal("地址相同时不应冲掉第三方标记")
	}
}
