package model

import (
	"strconv"
	"strings"
)

// DefaultHost 是站点默认域名.
const DefaultHost = "www.tucao.my"

// 站点域名的归一化.
//
// 与安卓端 SiteHost.normalize 的行为保持一致: 接受 www.tucao.my,
// https://www.tucao.my/, WWW.TUCAO.MY 等写法, 去掉协议, 路径,
// 空白与大小写差异, 允许带端口; 非法输入返回 false.

// NormalizeHost 把用户输入整理成主机名.
func NormalizeHost(raw string) (string, bool) {
	text := strings.TrimSpace(raw)
	if index := strings.Index(text, "://"); index >= 0 {
		scheme := text[:index]
		if !isScheme(scheme) {
			return "", false
		}
		text = text[index+3:]
	}
	if slash := strings.IndexByte(text, '/'); slash >= 0 {
		text = text[:slash]
	}
	text = strings.ToLower(strings.TrimSpace(text))
	if text == "" {
		return "", false
	}

	host := text
	port := ""
	if colon := strings.LastIndexByte(text, ':'); colon >= 0 {
		host = text[:colon]
		raw := text[colon+1:]
		if !isDigits(raw, 5) {
			return "", false
		}
		value, err := strconv.Atoi(raw)
		if err != nil || value < 1 || value > 65535 {
			return "", false
		}
		port = ":" + strconv.Itoa(value)
	}

	labels := strings.Split(host, ".")
	if len(labels) < 2 {
		return "", false
	}
	for _, label := range labels {
		if !isHostLabel(label) {
			return "", false
		}
	}
	return host + port, true
}

// isScheme 判断协议名是否合法, 只用来剥离前缀.
func isScheme(raw string) bool {
	if raw == "" {
		return false
	}
	for index, symbol := range raw {
		switch {
		case symbol >= 'a' && symbol <= 'z':
		case symbol >= 'A' && symbol <= 'Z':
		case index > 0 && (symbol >= '0' && symbol <= '9' || symbol == '+' || symbol == '-' || symbol == '.'):
		default:
			return false
		}
	}
	return true
}

// isHostLabel 判断单个域名标签是否合法, 不允许空标签与首尾连字符.
func isHostLabel(label string) bool {
	if label == "" {
		return false
	}
	for index, symbol := range label {
		switch {
		case symbol >= 'a' && symbol <= 'z':
		case symbol >= '0' && symbol <= '9':
		case symbol == '-' && index > 0 && index < len(label)-1:
		default:
			return false
		}
	}
	return true
}

// isDigits 判断字符串是否为纯数字且不超过给定长度.
func isDigits(raw string, max int) bool {
	if len(raw) == 0 || len(raw) > max {
		return false
	}
	for _, symbol := range raw {
		if symbol < '0' || symbol > '9' {
			return false
		}
	}
	return true
}
