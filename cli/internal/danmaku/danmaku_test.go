package danmaku

import (
	"bytes"
	"strings"
	"testing"

	"github.com/azazo1/tucao/cli/internal/api"
	"github.com/azazo1/tucao/cli/internal/model"
)

func sampleItems() []model.Danmaku {
	return []model.Danmaku{
		{Time: 5, Mode: 1, Position: model.PositionScroll, FontSize: 25, Color: 0xFFFFFF, Text: "第一条"},
		{Time: 1, Mode: 1, Position: model.PositionScroll, FontSize: 25, Color: 0xFF0000, Text: "第二条"},
		{Time: 5, Mode: 5, Position: model.PositionTop, FontSize: 25, Color: 0xFFFFFF, Text: "顶部"},
		{Time: 5, Mode: 4, Position: model.PositionBottom, FontSize: 25, Color: 0xFFFFFF, Text: "底部"},
	}
}

func TestApplyFiltersAndSorts(t *testing.T) {
	items := Apply(sampleItems(), Filter{})
	if len(items) != 4 {
		t.Fatalf("应保留全部弹幕: %d", len(items))
	}
	if items[0].Time != 1 {
		t.Fatalf("应按时间排序: %+v", items[0])
	}
	if got := Apply(sampleItems(), Filter{From: 5}); len(got) != 3 {
		t.Fatalf("按起始时间筛选结果不正确: %d", len(got))
	}
	if got := Apply(sampleItems(), Filter{To: 2}); len(got) != 1 {
		t.Fatalf("按结束时间筛选结果不正确: %d", len(got))
	}
	if got := Apply(sampleItems(), Filter{Limit: 2}); len(got) != 2 {
		t.Fatalf("按条数截断结果不正确: %d", len(got))
	}
}

func TestWriteASS(t *testing.T) {
	buffer := &bytes.Buffer{}
	if err := WriteASS(buffer, sampleItems(), DefaultOptions()); err != nil {
		t.Fatalf("导出 ass 失败: %v", err)
	}
	out := buffer.String()
	if !strings.Contains(out, "[Script Info]") || !strings.Contains(out, "[Events]") {
		t.Fatalf("ass 缺少必要的段: %s", out)
	}
	if strings.Count(out, "Dialogue:") != 4 {
		t.Fatalf("应生成 4 条字幕: %s", out)
	}
	if !strings.Contains(out, `{\move(`) {
		t.Fatalf("滚动弹幕应使用 move 效果: %s", out)
	}
	if !strings.Contains(out, `{\an8\pos(`) {
		t.Fatalf("顶部弹幕应使用 an8: %s", out)
	}
	if !strings.Contains(out, `{\an2\pos(`) {
		t.Fatalf("底部弹幕应使用 an2: %s", out)
	}
	// 时间 5 秒的两条滚动弹幕应落在不同的行上.
	lines := dialogueLines(out)
	ys := map[string]bool{}
	for _, line := range lines {
		if !strings.Contains(line, "第一条") && !strings.Contains(line, "第二条") {
			continue
		}
		start := strings.Index(line, "\\move(")
		if start < 0 {
			continue
		}
		body := line[start+len("\\move("):]
		parts := strings.Split(body[:strings.Index(body, ")")], ",")
		if len(parts) >= 2 {
			ys[parts[1]] = true
		}
	}
	if len(ys) < 2 {
		t.Fatalf("同一时刻的滚动弹幕应分行: %v", ys)
	}
}

func TestWriteASSRespectsHides(t *testing.T) {
	options := DefaultOptions()
	options.HideScroll = true
	options.HideTop = true
	buffer := &bytes.Buffer{}
	if err := WriteASS(buffer, sampleItems(), options); err != nil {
		t.Fatalf("导出 ass 失败: %v", err)
	}
	out := buffer.String()
	if strings.Contains(out, "第一条") || strings.Contains(out, "顶部") {
		t.Fatalf("隐藏的类型不应出现在字幕里: %s", out)
	}
	if !strings.Contains(out, "底部") {
		t.Fatalf("未隐藏的类型应保留: %s", out)
	}
}

func TestWriteASSEscapesText(t *testing.T) {
	items := []model.Danmaku{{
		Time: 1, Mode: 1, Position: model.PositionScroll, FontSize: 25, Text: "带{花括号}\n换行",
	}}
	buffer := &bytes.Buffer{}
	if err := WriteASS(buffer, items, DefaultOptions()); err != nil {
		t.Fatalf("导出 ass 失败: %v", err)
	}
	out := buffer.String()
	if !strings.Contains(out, `\{花括号\}`) {
		t.Fatalf("花括号应被转义: %s", out)
	}
	if !strings.Contains(out, `\N`) {
		t.Fatalf("换行应转成 ass 的换行符: %s", out)
	}
}

func TestWriteXMLRoundTrip(t *testing.T) {
	items := Apply(sampleItems(), Filter{})
	buffer := &bytes.Buffer{}
	if err := WriteXML(buffer, items); err != nil {
		t.Fatalf("导出 xml 失败: %v", err)
	}
	parsed, err := api.ParseDanmakuXML(buffer.String())
	if err != nil {
		t.Fatalf("导出的 xml 无法再解析: %v", err)
	}
	if len(parsed) != len(items) {
		t.Fatalf("导出与解析条数不一致: %d != %d", len(parsed), len(items))
	}
	if parsed[0].Text != items[0].Text || parsed[0].Time != items[0].Time {
		t.Fatalf("导出内容不一致: %+v", parsed[0])
	}
	if parsed[0].Color != items[0].Color {
		t.Fatalf("颜色没有正确导出: %+v", parsed[0])
	}
}

func TestWriteXMLEscapesSpecialCharacters(t *testing.T) {
	items := []model.Danmaku{{Time: 1, Mode: 1, Text: `<a & b> "引号"`}}
	buffer := &bytes.Buffer{}
	if err := WriteXML(buffer, items); err != nil {
		t.Fatalf("导出 xml 失败: %v", err)
	}
	if !strings.Contains(buffer.String(), "&lt;a &amp; b&gt;") {
		t.Fatalf("特殊字符应被转义: %s", buffer.String())
	}
	if _, err := api.ParseDanmakuXML(buffer.String()); err != nil {
		t.Fatalf("转义后的 xml 应仍可解析: %v", err)
	}
}

func TestWriteText(t *testing.T) {
	items := Apply(sampleItems(), Filter{})
	buffer := &bytes.Buffer{}
	if err := WriteText(buffer, items); err != nil {
		t.Fatalf("导出文本失败: %v", err)
	}
	lines := strings.Split(strings.TrimSpace(buffer.String()), "\n")
	if len(lines) != len(items) {
		t.Fatalf("导出行数不正确: %d", len(lines))
	}
	if lines[0] != "00:01.00\t第二条" {
		t.Fatalf("首行格式不正确: %q", lines[0])
	}
}

func TestOptionsNormalized(t *testing.T) {
	options := Options{FontSize: 999, DurationSeconds: 100, Area: 5, Opacity: -1, Width: 0}
	normalized := options.normalized()
	if normalized.FontSize != DefaultOptions().FontSize || normalized.DurationSeconds != DefaultOptions().DurationSeconds {
		t.Fatalf("越界参数应回落到默认值: %+v", normalized)
	}
	if normalized.Width <= 0 || normalized.Height <= 0 {
		t.Fatalf("画面尺寸应有默认值: %+v", normalized)
	}
}

// dialogueLines 取出 ass 里的字幕行.
func dialogueLines(raw string) []string {
	lines := []string{}
	for _, line := range strings.Split(raw, "\n") {
		if strings.HasPrefix(line, "Dialogue:") {
			lines = append(lines, line)
		}
	}
	return lines
}
