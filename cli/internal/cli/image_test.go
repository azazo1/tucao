package cli

import (
	"testing"

	"github.com/azazo1/tucao/cli/internal/model"
)

func TestParseImageKinds(t *testing.T) {
	cases := map[string][]string{
		"":         {imageAvatar, imageBanner},
		" avatar ": {imageAvatar},
		"BANNER":   {imageBanner},
	}
	for raw, want := range cases {
		got, err := parseImageKinds(raw)
		if err != nil {
			t.Fatalf("parseImageKinds(%q) 失败: %v", raw, err)
		}
		if len(got) != len(want) {
			t.Fatalf("parseImageKinds(%q) = %v, 期望 %v", raw, got, want)
		}
		for index := range want {
			if got[index] != want[index] {
				t.Fatalf("parseImageKinds(%q) = %v, 期望 %v", raw, got, want)
			}
		}
	}
	for _, raw := range []string{"cover", "all", "avatar,banner"} {
		if _, err := parseImageKinds(raw); err == nil {
			t.Fatalf("parseImageKinds(%q) 应当报错", raw)
		}
	}
}

func TestImageExtension(t *testing.T) {
	cases := map[string]string{
		"https://www.tucao.my/uploadfile/2023/0822/20230822065236713.jpg": ".jpg",
		"https://www.tucao.my/uploadfile/avatar/46/4/453520/180x180.JPG":  ".jpg",
		"https://www.tucao.my/uploadfile/2023/a.png?x=1":                  ".png",
		"https://www.tucao.my/uploadfile/2023/a.gif#frag":                 ".gif",
		"https://www.tucao.my/uploadfile/avatar/46/4/453520/180x180":      ".jpg",
		"https://www.tucao.my/uploadfile/avatar.aspx?id=1":                ".jpg",
		"https://www.tucao.my/uploadfile/2023/a.webp":                     ".webp",
	}
	for raw, want := range cases {
		if got := imageExtension(raw); got != want {
			t.Fatalf("imageExtension(%q) = %q, 期望 %q", raw, got, want)
		}
	}
}

func TestImageFileName(t *testing.T) {
	got := imageFileName("442223", imageBanner, "https://www.tucao.my/uploadfile/2023/a.png")
	if want := "442223-banner.png"; got != want {
		t.Fatalf("imageFileName = %q, 期望 %q", got, want)
	}
}

func TestImageTargets(t *testing.T) {
	space := model.Space{UserID: 442223, Avatar: "a.jpg", Banner: "b.jpg"}
	if got := imageTargets(space, []string{imageBanner}); len(got) != 1 || got[0].source != "b.jpg" {
		t.Fatalf("只取横幅时结果不对: %+v", got)
	}
	got := imageTargets(space, []string{imageBanner, imageAvatar})
	if len(got) != 2 || got[0].kind != imageBanner || got[1].kind != imageAvatar {
		t.Fatalf("下载顺序应当跟随 kinds: %+v", got)
	}
}
