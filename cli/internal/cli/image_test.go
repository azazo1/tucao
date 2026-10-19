package cli

import (
	"path/filepath"
	"testing"
	"time"

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

func TestImageFileName(t *testing.T) {
	got := imageFileName("out", "442223", imageBanner, ".png")
	if want := filepath.Join("out", "442223-banner.png"); got != want {
		t.Fatalf("imageFileName = %q, 期望 %q", got, want)
	}
}

func TestImageSizeText(t *testing.T) {
	if got := imageSizeText(imageItem{Width: 960, Height: 300}); got != "960x300" {
		t.Fatalf("imageSizeText = %q, 期望 960x300", got)
	}
	if got := imageSizeText(imageItem{Width: 180}); got != "" {
		t.Fatalf("尺寸不全时应当返回空串, 实际 %q", got)
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

func TestWithCacheBust(t *testing.T) {
	stamp := time.Date(2026, 10, 19, 19, 30, 0, 0, time.UTC)
	avatar := "https://www.tucao.my/phpsso_server/uploadfile/avatar/47/6/465088/180x180.jpg"

	if got, want := withCacheBust(avatar, stamp), avatar+"?_t=20261019193000"; got != want {
		t.Fatalf("withCacheBust = %q, 期望 %q", got, want)
	}

	// 站点自己带的参数要留着, 旧的版本参数换成新的.
	withQuery := "https://www.tucao.my/a.jpg?size=180&_t=old"
	if got, want := withCacheBust(withQuery, stamp), "https://www.tucao.my/a.jpg?_t=20261019193000&size=180"; got != want {
		t.Fatalf("带原有参数时 withCacheBust = %q, 期望 %q", got, want)
	}

	// 空地址与相对地址原样返回, 免得把站点给的原样地址改坏.
	for _, raw := range []string{"", "   ", "/uploadfile/a.jpg"} {
		if got := withCacheBust(raw, stamp); got != raw {
			t.Fatalf("withCacheBust(%q) 不该改写, 实际 %q", raw, got)
		}
	}
}
