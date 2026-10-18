package danmaku

import (
	"encoding/xml"
	"fmt"
	"io"
	"math"
	"sort"
	"strings"

	"github.com/azazo1/tucao/cli/internal/model"
)

// Filter 是弹幕筛选条件.
type Filter struct {
	// From 与 To 按出现时间筛选, 秒; To 为 0 表示不限.
	From float64
	To   float64
	// Limit 大于 0 时只保留前若干条, 0 表示不截断.
	Limit int
}

// Apply 按筛选条件挑出弹幕, 同时按时间排序.
func Apply(items []model.Danmaku, filter Filter) []model.Danmaku {
	result := make([]model.Danmaku, 0, len(items))
	for _, item := range items {
		if item.Time < filter.From {
			continue
		}
		if filter.To > 0 && item.Time > filter.To {
			continue
		}
		result = append(result, item)
	}
	sort.SliceStable(result, func(left, right int) bool { return result[left].Time < result[right].Time })
	if filter.Limit > 0 && len(result) > filter.Limit {
		result = result[:filter.Limit]
	}
	return result
}

// WriteXML 按站点格式导出弹幕, 便于其他工具直接复用.
func WriteXML(destination io.Writer, items []model.Danmaku) error {
	if _, err := io.WriteString(destination, "<i>\n"); err != nil {
		return err
	}
	for _, item := range items {
		attribute := fmt.Sprintf("%s,%d,%d,%d,%d",
			trimFloat(item.Time), item.Mode, item.FontSize, item.Color, item.Timestamp)
		if _, err := fmt.Fprintf(destination, "\t<d p=%q>%s</d>\n",
			attribute, escapeXMLText(item.Text)); err != nil {
			return err
		}
	}
	_, err := io.WriteString(destination, "</i>\n")
	return err
}

// WriteText 导出纯文本, 每行是时间加内容.
func WriteText(destination io.Writer, items []model.Danmaku) error {
	for _, item := range items {
		if _, err := fmt.Fprintf(destination, "%s\t%s\n", timeText(item.Time), item.Text); err != nil {
			return err
		}
	}
	return nil
}

// timeText 输出 mm:ss.ff 形式的时间.
func timeText(seconds float64) string {
	if seconds < 0 {
		seconds = 0
	}
	total := int(math.Round(seconds * 100))
	minutes := total / 6000
	rest := (total % 6000) / 100
	centis := total % 100
	return fmt.Sprintf("%02d:%02d.%02d", minutes, rest, centis)
}

// trimFloat 去掉浮点数多余的零.
func trimFloat(value float64) string {
	return strings.TrimSuffix(strings.TrimSuffix(fmt.Sprintf("%.2f", value), "0"), ".")
}

// escapeXMLText 转义 xml 文本.
func escapeXMLText(text string) string {
	var builder strings.Builder
	if err := xml.EscapeText(&builder, []byte(text)); err != nil {
		return text
	}
	return builder.String()
}
