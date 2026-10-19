package api

import "strings"

// placeholderImagePath 是站点在"没有这张图"时给出的占位图地址.
//
// 没有设置横幅的账号, 空间页里 img.banner 的背景图就指向它, 图片本身是
// 一张 90x60 的空白图, 下载下来没有任何意义.
const placeholderImagePath = "/statics/images/nopic.gif"

// IsPlaceholderImage 判断图片地址是不是站点的占位图.
func IsPlaceholderImage(source string) bool {
	text := strings.TrimSpace(source)
	if text == "" {
		return false
	}
	if index := strings.IndexAny(text, "?#"); index >= 0 {
		text = text[:index]
	}
	return strings.HasSuffix(strings.ToLower(text), placeholderImagePath)
}
