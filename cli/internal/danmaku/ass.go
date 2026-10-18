// Package danmaku 负责把站点弹幕导出成 ass, xml 与纯文本.
package danmaku

import (
	"fmt"
	"io"
	"math"
	"sort"
	"strings"

	"github.com/mattn/go-runewidth"

	"github.com/azazo1/tucao/cli/internal/model"
)

// Options 是 ass 导出参数.
type Options struct {
	Font                  string
	FontSize              int
	DurationSeconds       float64
	StaticDurationSeconds float64
	// Area 是弹幕显示区域占画面高度的比例.
	Area        float64
	Opacity     float64
	StrokeWidth float64
	LineHeight  float64
	HideScroll  bool
	HideTop     bool
	HideBottom  bool
	Width       int
	Height      int
}

// DefaultOptions 返回默认排版参数, 与配置里的默认值保持一致.
func DefaultOptions() Options {
	return Options{
		Font:                  "sans-serif",
		FontSize:              25,
		DurationSeconds:       8,
		StaticDurationSeconds: 5,
		Area:                  1,
		Opacity:               1,
		StrokeWidth:           1.5,
		LineHeight:            1.6,
		Width:                 1280,
		Height:                720,
	}
}

// normalized 收敛不合法的排版参数, 保证导出的字幕不会因为配置错误而崩.
func (o Options) normalized() Options {
	defaults := DefaultOptions()
	if strings.TrimSpace(o.Font) == "" {
		o.Font = defaults.Font
	}
	if o.FontSize < 8 || o.FontSize > 64 {
		o.FontSize = defaults.FontSize
	}
	if o.DurationSeconds < 1 || o.DurationSeconds > 30 {
		o.DurationSeconds = defaults.DurationSeconds
	}
	if o.StaticDurationSeconds < 1 || o.StaticDurationSeconds > 30 {
		o.StaticDurationSeconds = defaults.StaticDurationSeconds
	}
	if o.Area < 0.1 || o.Area > 1 {
		o.Area = defaults.Area
	}
	if o.Opacity < 0 || o.Opacity > 1 {
		o.Opacity = defaults.Opacity
	}
	if o.StrokeWidth < 0 || o.StrokeWidth > 5 {
		o.StrokeWidth = defaults.StrokeWidth
	}
	if o.LineHeight < 1 || o.LineHeight > 3 {
		o.LineHeight = defaults.LineHeight
	}
	if o.Width <= 0 {
		o.Width = defaults.Width
	}
	if o.Height <= 0 {
		o.Height = defaults.Height
	}
	return o
}

const assHeader = `[Script Info]
ScriptType: v4.00+
Collisions: Normal
PlayResX: %d
PlayResY: %d
WrapStyle: 2
ScaledBorderAndShadow: yes

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Tucao,%s,%d,%s,%s,&H00000000,&H00000000,0,0,0,0,100,100,0,0,1,%s,0,2,20,20,20,1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
`

// WriteASS 把弹幕写成 ass 字幕.
//
// 滚动弹幕按出现时间分配行, 同一时刻的弹幕不会叠在一起;
// 顶部与底部弹幕各自占用上下两端的行.
func WriteASS(destination io.Writer, items []model.Danmaku, options Options) error {
	options = options.normalized()
	alpha := int(math.Round((1 - options.Opacity) * 255))
	primary := assColor(0xFFFFFF, alpha)
	style := fmt.Sprintf(assHeader, options.Width, options.Height,
		options.Font, options.FontSize, primary, primary, formatNumber(options.StrokeWidth))
	if _, err := io.WriteString(destination, style); err != nil {
		return err
	}
	for _, line := range assEvents(items, options) {
		if _, err := fmt.Fprintln(destination, line); err != nil {
			return err
		}
	}
	return nil
}

func assEvents(items []model.Danmaku, options Options) []string {
	sorted := make([]model.Danmaku, 0, len(items))
	for _, item := range items {
		if item.Text == "" {
			continue
		}
		switch item.Position {
		case model.PositionTop:
			if options.HideTop {
				continue
			}
		case model.PositionBottom:
			if options.HideBottom {
				continue
			}
		default:
			if options.HideScroll {
				continue
			}
		}
		sorted = append(sorted, item)
	}
	sort.SliceStable(sorted, func(left, right int) bool { return sorted[left].Time < sorted[right].Time })

	lineHeight := float64(options.FontSize) * options.LineHeight
	laneCount := int(float64(options.Height) * options.Area / lineHeight)
	if laneCount < 1 {
		laneCount = 1
	}
	scrollLanes := newLanes(laneCount)
	topLanes := newLanes(laneCount)
	bottomLanes := newLanes(laneCount)

	events := make([]string, 0, len(sorted))
	for _, item := range sorted {
		text := escapeASSText(item.Text)
		width := float64(runewidth.StringWidth(item.Text)) * float64(options.FontSize)
		var (
			start  = item.Time
			end    float64
			effect string
		)
		switch item.Position {
		case model.PositionTop:
			lane := topLanes.take(start)
			end = start + options.StaticDurationSeconds
			topLanes.free[lane] = end
			effect = fmt.Sprintf(`{\an8\pos(%d,%d)}`, options.Width/2, int(float64(lane)*lineHeight))
		case model.PositionBottom:
			lane := bottomLanes.take(start)
			end = start + options.StaticDurationSeconds
			bottomLanes.free[lane] = end
			effect = fmt.Sprintf(`{\an2\pos(%d,%d)}`, options.Width/2,
				options.Height-int(float64(lane)*lineHeight))
		default:
			lane := scrollLanes.take(start)
			end = start + options.DurationSeconds
			scrollLanes.free[lane] = end
			y := int(float64(lane)*lineHeight + lineHeight/2)
			from := options.Width + int(width/2)
			to := -int(width / 2)
			effect = fmt.Sprintf(`{\move(%d,%d,%d,%d,0,%d)}`, from, y, to, y,
				int(math.Round(options.DurationSeconds*1000)))
		}
		events = append(events, fmt.Sprintf("Dialogue: 0,%s,%s,Tucao,,0,0,0,,%s%s",
			assTimestamp(start), assTimestamp(end), effect, text))
	}
	return events
}

// lanes 记录每一行弹幕的可用时间.
type lanes struct {
	free []float64
}

func newLanes(count int) *lanes {
	lanes := &lanes{free: make([]float64, count)}
	for index := range lanes.free {
		lanes.free[index] = math.Inf(-1)
	}
	return lanes
}

// take 取一行, 优先取已经空出来的最上面一行, 全都占用时取最早释放的一行.
func (l *lanes) take(start float64) int {
	for index, free := range l.free {
		if free <= start {
			return index
		}
	}
	best := 0
	for index, free := range l.free {
		if free < l.free[best] {
			best = index
		}
	}
	return best
}

// assColor 把十进制 rgb 转成 ass 的 &HAABBGGRR.
func assColor(rgb, alpha int) string {
	red := (rgb >> 16) & 0xFF
	green := (rgb >> 8) & 0xFF
	blue := rgb & 0xFF
	return fmt.Sprintf("&H%02X%02X%02X%02X", alpha, blue, green, red)
}

// assTimestamp 输出 ass 的时间格式 H:MM:SS.cc.
func assTimestamp(seconds float64) string {
	if seconds < 0 {
		seconds = 0
	}
	total := int(math.Round(seconds * 100))
	hours := total / 360000
	minutes := (total % 360000) / 6000
	rest := (total % 6000) / 100
	centis := total % 100
	return fmt.Sprintf("%d:%02d:%02d.%02d", hours, minutes, rest, centis)
}

// escapeASSText 转义 ass 里需要转义的字符.
func escapeASSText(text string) string {
	replacer := strings.NewReplacer(
		`\`, `\\`,
		"{", `\{`,
		"}", `\}`,
		"\r", "",
		"\n", `\N`,
	)
	return replacer.Replace(text)
}

func formatNumber(value float64) string {
	return strings.TrimSuffix(strings.TrimSuffix(fmt.Sprintf("%.2f", value), "0"), ".")
}
