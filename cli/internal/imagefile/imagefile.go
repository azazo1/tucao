// Package imagefile 按内容识别图片文件.
//
// 站点上的图片名不副实: 头像地址以 .jpg 结尾, 内容却可能是 PNG; 没有设置
// 头像的账号还会返回一个只有文件头的小文件. 因此下载完成后要按内容判断
// 究竟拿到了什么, 认不出来的内容不能当成图片留下.
package imagefile

import (
	"bytes"
	"errors"
	"image"
	"io"
	"os"

	// 注册标准库里的三种解码器, 供 image.DecodeConfig 使用.
	_ "image/gif"
	_ "image/jpeg"
	_ "image/png"
)

// Info 是一张图片的格式与像素尺寸.
type Info struct {
	// Format 是图片格式, 取值例如 png, jpeg 与 gif.
	Format string
	// Extension 是格式对应的带点扩展名, 例如 .png.
	Extension string
	// Width 与 Height 是像素尺寸, 只按文件头识别格式时为 0.
	Width  int
	Height int
}

// ErrNotImage 表示内容不是可识别的图片.
var ErrNotImage = errors.New("内容不是可识别的图片")

// formatExtensions 是解码器格式名与扩展名的对应关系.
var formatExtensions = map[string]string{
	"png":  ".png",
	"jpeg": ".jpg",
	"gif":  ".gif",
}

// magicFormats 是标准库解码器之外的格式, 只能按文件头认出格式, 拿不到尺寸.
var magicFormats = []struct {
	format    string
	extension string
	// offset 与 magic 描述文件头里的一段特征字节.
	offset int
	magic  []byte
}{
	{format: "webp", extension: ".webp", offset: 8, magic: []byte("WEBP")},
	{format: "bmp", extension: ".bmp", offset: 0, magic: []byte("BM")},
}

// Inspect 按内容识别一张图片.
//
// 先交给标准库解码器读文件头, 失败时再匹配常见格式的魔数; 两者都不认,
// 说明拿到的不是完整图片, 例如只有 8 字节文件头的坏文件.
func Inspect(path string) (Info, error) {
	file, err := os.Open(path)
	if err != nil {
		return Info{}, err
	}
	defer file.Close()

	if config, format, err := image.DecodeConfig(file); err == nil {
		extension, ok := formatExtensions[format]
		if !ok {
			return Info{}, ErrNotImage
		}
		return Info{Format: format, Extension: extension, Width: config.Width, Height: config.Height}, nil
	}

	header := make([]byte, 32)
	count, err := file.ReadAt(header, 0)
	if err != nil && !errors.Is(err, io.EOF) {
		return Info{}, err
	}
	header = header[:count]
	for _, candidate := range magicFormats {
		if matchesHeader(header, candidate.offset, candidate.magic) {
			return Info{Format: candidate.format, Extension: candidate.extension}, nil
		}
	}
	return Info{}, ErrNotImage
}

// Extensions 返回可以落盘的图片扩展名.
//
// 调用方用它回查同名的已有文件, 因为最终扩展名要等认出内容之后才知道.
func Extensions() []string {
	return []string{".jpg", ".png", ".gif", ".webp", ".bmp"}
}

// matchesHeader 判断文件头里是否出现指定的特征字节.
func matchesHeader(header []byte, offset int, magic []byte) bool {
	if len(header) < offset+len(magic) {
		return false
	}
	return bytes.Equal(header[offset:offset+len(magic)], magic)
}
