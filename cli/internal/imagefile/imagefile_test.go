package imagefile

import (
	"errors"
	"image"
	"image/color"
	"image/gif"
	"image/jpeg"
	"image/png"
	"os"
	"path/filepath"
	"testing"
)

// writeEncoded 用给定编码器写一张纯色图片, 返回文件路径.
func writeEncoded(t *testing.T, name string, width, height int, encode func(*os.File) error) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), name)
	file, err := os.Create(path)
	if err != nil {
		t.Fatalf("创建测试文件失败: %v", err)
	}
	if err := encode(file); err != nil {
		file.Close()
		t.Fatalf("写入测试图片失败: %v", err)
	}
	if err := file.Close(); err != nil {
		t.Fatalf("关闭测试图片失败: %v", err)
	}
	return path
}

func solidImage(width, height int) *image.RGBA {
	picture := image.NewRGBA(image.Rect(0, 0, width, height))
	for x := 0; x < width; x++ {
		for y := 0; y < height; y++ {
			picture.Set(x, y, color.RGBA{R: 0x20, G: 0x60, B: 0xa0, A: 0xff})
		}
	}
	return picture
}

func TestInspectKnownFormats(t *testing.T) {
	cases := []struct {
		name      string
		file      string
		format    string
		extension string
		width     int
		height    int
	}{
		{
			name: "png", file: "a.jpg", format: "png", extension: ".png", width: 4, height: 3,
			// 站点的头像就是 .jpg 结尾的 PNG, 后缀不该影响识别结果.
		},
		{name: "jpeg", file: "b.jpg", format: "jpeg", extension: ".jpg", width: 5, height: 2},
		{name: "gif", file: "c.gif", format: "gif", extension: ".gif", width: 3, height: 6},
	}
	for _, testCase := range cases {
		t.Run(testCase.name, func(t *testing.T) {
			picture := solidImage(testCase.width, testCase.height)
			var path string
			switch testCase.format {
			case "png":
				path = writeEncoded(t, testCase.file, testCase.width, testCase.height, func(file *os.File) error {
					return png.Encode(file, picture)
				})
			case "jpeg":
				path = writeEncoded(t, testCase.file, testCase.width, testCase.height, func(file *os.File) error {
					return jpeg.Encode(file, picture, nil)
				})
			case "gif":
				path = writeEncoded(t, testCase.file, testCase.width, testCase.height, func(file *os.File) error {
					return gif.Encode(file, picture, nil)
				})
			}
			info, err := Inspect(path)
			if err != nil {
				t.Fatalf("Inspect(%s) 失败: %v", testCase.file, err)
			}
			if info.Format != testCase.format || info.Extension != testCase.extension {
				t.Fatalf("格式识别为 %s%s, 期望 %s%s", info.Format, info.Extension, testCase.format, testCase.extension)
			}
			if info.Width != testCase.width || info.Height != testCase.height {
				t.Fatalf("尺寸识别为 %dx%d, 期望 %dx%d", info.Width, info.Height, testCase.width, testCase.height)
			}
		})
	}
}

func TestInspectRejectsBrokenContent(t *testing.T) {
	directory := t.TempDir()
	cases := map[string][]byte{
		// 站点给没有头像的账号返回的就是这样的文件: 只有 PNG 文件头.
		"header-only.png": {0x89, 'P', 'N', 'G', 0x0d, 0x0a, 0x1a, 0x0a},
		"empty.jpg":       {},
		"page.html":       []byte("<html><head><title>404</title></head></html>"),
	}
	for name, content := range cases {
		path := filepath.Join(directory, name)
		if err := os.WriteFile(path, content, 0o644); err != nil {
			t.Fatalf("写入测试文件失败: %v", err)
		}
		if _, err := Inspect(path); !errors.Is(err, ErrNotImage) {
			t.Fatalf("Inspect(%s) 应当报 ErrNotImage, 实际 %v", name, err)
		}
	}
}

func TestInspectWebPHeader(t *testing.T) {
	path := filepath.Join(t.TempDir(), "a.webp")
	header := append([]byte("RIFF\x00\x00\x00\x00WEBP"), make([]byte, 20)...)
	if err := os.WriteFile(path, header, 0o644); err != nil {
		t.Fatalf("写入测试文件失败: %v", err)
	}
	info, err := Inspect(path)
	if err != nil {
		t.Fatalf("Inspect(webp) 失败: %v", err)
	}
	if info.Format != "webp" || info.Extension != ".webp" {
		t.Fatalf("格式识别为 %s%s, 期望 webp.webp", info.Format, info.Extension)
	}
}
