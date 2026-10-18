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
