package cli

import (
	"fmt"
	"os"
	"regexp"
	"strconv"
	"strings"
	"time"

	"github.com/azazo1/tucao/cli/internal/api"
)

var (
	// 站内播放页地址里的 hid, 兼容 /play/h123/ 与 /play/123/ 两种写法.
	playIDPattern = regexp.MustCompile(`/play/h?(\d+)/`)
	// 用户空间地址里的 uid.
	userIDPattern = regexp.MustCompile(`/play/u(\d+)/`)
	// 裸 hid 写法, 允许带 h 前缀.
	bareHIDPattern = regexp.MustCompile(`^h?(\d+)$`)
	// 裸 uid 写法.
	bareUIDPattern = regexp.MustCompile(`^u?(\d+)$`)
)

// parseHID 把各种写法的视频编号解析成纯数字 hid.
//
// 接受 4107860, h4107860, /play/h4107860/, 以及完整的站点播放页地址.
func parseHID(raw string) (string, error) {
	text := strings.TrimSpace(raw)
	if text == "" {
		return "", fmt.Errorf("缺少视频编号")
	}
	if match := playIDPattern.FindStringSubmatch(text); match != nil {
		return match[1], nil
	}
	if match := bareHIDPattern.FindStringSubmatch(text); match != nil {
		return match[1], nil
	}
	return "", fmt.Errorf("无法识别的视频编号: %s", raw)
}

// parseUID 把各种写法的用户编号解析成整数 uid.
//
// 接受 4107860, u4107860, /play/u4107860/, 以及完整的用户空间地址.
func parseUID(raw string) (int, error) {
	text := strings.TrimSpace(raw)
	if text == "" {
		return 0, fmt.Errorf("缺少用户编号")
	}
	var digits string
	switch match := userIDPattern.FindStringSubmatch(text); {
	case match != nil:
		digits = match[1]
	default:
		if match := bareUIDPattern.FindStringSubmatch(text); match != nil {
			digits = match[1]
		}
	}
	if digits == "" {
		return 0, fmt.Errorf("无法识别的用户编号: %s", raw)
	}
	value, err := strconv.Atoi(digits)
	if err != nil || value <= 0 {
		return 0, fmt.Errorf("无法识别的用户编号: %s", raw)
	}
	return value, nil
}

// prepareDownloadDir 解析输出目录并按需创建.
//
// 命令行参数优先, 其次是配置里的下载目录, 都没有时落在当前目录.
func (a *App) prepareDownloadDir(flagValue string) (string, error) {
	directory := strings.TrimSpace(flagValue)
	if directory == "" {
		directory = a.Config.Download.OutputDir
	}
	if directory == "" {
		directory = "."
	}
	if err := os.MkdirAll(directory, 0o755); err != nil {
		return "", api.WrapError(api.CodeInternal, "下载", "创建目录失败: "+directory, err)
	}
	return directory, nil
}

// formatTimestamp 把秒级时间戳格式化成本地时间.
func formatTimestamp(seconds int64) string {
	if seconds <= 0 {
		return ""
	}
	return time.Unix(seconds, 0).Format("2006-01-02 15:04:05")
}

// humanCount 按站点习惯把大数字显示成 万 与 亿.
func humanCount(count int) string {
	switch {
	case count < 10000:
		return strconv.Itoa(count)
	case count < 100000000:
		return trimDecimal(float64(count)/10000) + "万"
	default:
		return trimDecimal(float64(count)/100000000) + "亿"
	}
}

func trimDecimal(value float64) string {
	text := strconv.FormatFloat(value, 'f', 1, 64)
	return strings.TrimSuffix(text, ".0")
}

// formatDuration 把秒数格式化成 mm:ss 或 hh:mm:ss.
func formatDuration(seconds float64) string {
	if seconds < 0 {
		seconds = 0
	}
	total := int(seconds)
	hours := total / 3600
	minutes := (total % 3600) / 60
	rest := total % 60
	if hours > 0 {
		return fmt.Sprintf("%d:%02d:%02d", hours, minutes, rest)
	}
	return fmt.Sprintf("%02d:%02d", minutes, rest)
}

// parseTimeSpec 解析弹幕或进度参数里的时间写法.
//
// 支持 12.5, 12.5s, 1m20s, 1:20 与 1:20:00 四种写法.
func parseTimeSpec(raw string) (float64, error) {
	text := strings.ToLower(strings.TrimSpace(raw))
	if text == "" {
		return 0, fmt.Errorf("时间不能为空")
	}
	if strings.Contains(text, ":") {
		parts := strings.Split(text, ":")
		if len(parts) > 3 {
			return 0, fmt.Errorf("无法识别的时间: %s", raw)
		}
		seconds := 0.0
		for _, part := range parts {
			value, err := strconv.ParseFloat(strings.TrimSpace(part), 64)
			if err != nil || value < 0 {
				return 0, fmt.Errorf("无法识别的时间: %s", raw)
			}
			seconds = seconds*60 + value
		}
		return seconds, nil
	}
	if strings.ContainsAny(text, "ms") {
		seconds := 0.0
		number := ""
		for _, symbol := range text {
			switch {
			case symbol >= '0' && symbol <= '9' || symbol == '.':
				number += string(symbol)
			case symbol == 'm' || symbol == 's':
				if number == "" {
					return 0, fmt.Errorf("无法识别的时间: %s", raw)
				}
				value, err := strconv.ParseFloat(number, 64)
				if err != nil || value < 0 {
					return 0, fmt.Errorf("无法识别的时间: %s", raw)
				}
				if symbol == 'm' {
					seconds += value * 60
				} else {
					seconds += value
				}
				number = ""
			default:
				return 0, fmt.Errorf("无法识别的时间: %s", raw)
			}
		}
		if number != "" {
			return 0, fmt.Errorf("无法识别的时间: %s", raw)
		}
		return seconds, nil
	}
	value, err := strconv.ParseFloat(text, 64)
	if err != nil || value < 0 {
		return 0, fmt.Errorf("无法识别的时间: %s", raw)
	}
	return value, nil
}
