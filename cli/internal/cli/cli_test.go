package cli

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/azazo1/tucao/cli/internal/output"
)

func TestParseHID(t *testing.T) {
	cases := map[string]string{
		"4107860":                               "4107860",
		"h4107860":                              "4107860",
		"/play/h4107860/":                       "4107860",
		"https://www.tucao.my/play/h4107860/#2": "4107860",
		"https://www.tucao.my/play/4107860/":    "4107860",
		" 4107860 ":                             "4107860",
	}
	for raw, want := range cases {
		got, err := parseHID(raw)
		if err != nil {
			t.Fatalf("parseHID(%q) 失败: %v", raw, err)
		}
		if got != want {
			t.Fatalf("parseHID(%q) = %q, 期望 %q", raw, got, want)
		}
	}
	for _, raw := range []string{"", "abc", "h", "play/h/"} {
		if _, err := parseHID(raw); err == nil {
			t.Fatalf("parseHID(%q) 应当报错", raw)
		}
	}
}

func TestParseUID(t *testing.T) {
	cases := map[string]int{
		"442223":                             442223,
		"u442223":                            442223,
		"/play/u442223/":                     442223,
		"https://www.tucao.my/play/u442223/": 442223,
	}
	for raw, want := range cases {
		got, err := parseUID(raw)
		if err != nil {
			t.Fatalf("parseUID(%q) 失败: %v", raw, err)
		}
		if got != want {
			t.Fatalf("parseUID(%q) = %d, 期望 %d", raw, got, want)
		}
	}
	for _, raw := range []string{"", "0", "u0", "abc"} {
		if _, err := parseUID(raw); err == nil {
			t.Fatalf("parseUID(%q) 应当报错", raw)
		}
	}
}

func TestParseTimeSpec(t *testing.T) {
	cases := map[string]float64{
		"12.5":    12.5,
		"12.5s":   12.5,
		"1m20s":   80,
		"1:20":    80,
		"1:20:00": 4800,
		"0":       0,
	}
	for raw, want := range cases {
		got, err := parseTimeSpec(raw)
		if err != nil {
			t.Fatalf("parseTimeSpec(%q) 失败: %v", raw, err)
		}
		if got != want {
			t.Fatalf("parseTimeSpec(%q) = %v, 期望 %v", raw, got, want)
		}
	}
	for _, raw := range []string{"", "abc", "-1", "1:2:3:4", "m"} {
		if _, err := parseTimeSpec(raw); err == nil {
			t.Fatalf("parseTimeSpec(%q) 应当报错", raw)
		}
	}
}

func TestParseColorAndMode(t *testing.T) {
	if value, err := parseColor("#FF0000"); err != nil || value != 0xFF0000 {
		t.Fatalf("十六进制颜色解析失败: %v %d", err, value)
	}
	if value, err := parseColor("16711680"); err != nil || value != 0xFF0000 {
		t.Fatalf("十进制颜色解析失败: %v %d", err, value)
	}
	if value, err := parseColor(""); err != nil || value != 0xFFFFFF {
		t.Fatalf("默认颜色应为白色: %v %d", err, value)
	}
	for _, raw := range []string{"#GGGGGG", "16777216", "-1", "红色"} {
		if _, err := parseColor(raw); err == nil {
			t.Fatalf("parseColor(%q) 应当报错", raw)
		}
	}
	if mode, err := parseDanmakuMode("top"); err != nil || mode != 5 {
		t.Fatalf("top 应映射为 5: %v %d", err, mode)
	}
	if mode, err := parseDanmakuMode("底部"); err != nil || mode != 4 {
		t.Fatalf("底部应映射为 4: %v %d", err, mode)
	}
	if _, err := parseDanmakuMode("中间"); err == nil {
		t.Fatal("未知位置应当报错")
	}
}

func TestFormatting(t *testing.T) {
	if got := humanCount(9999); got != "9999" {
		t.Fatalf("humanCount(9999) = %q", got)
	}
	if got := humanCount(12000); got != "1.2万" {
		t.Fatalf("humanCount(12000) = %q", got)
	}
	if got := humanCount(150000000); got != "1.5亿" {
		t.Fatalf("humanCount(150000000) = %q", got)
	}
	if got := formatDuration(80); got != "01:20" {
		t.Fatalf("formatDuration(80) = %q", got)
	}
	if got := formatDuration(3661); got != "1:01:01" {
		t.Fatalf("formatDuration(3661) = %q", got)
	}
	if got := formatBytes(1536); got != "1.5 KB" {
		t.Fatalf("formatBytes(1536) = %q", got)
	}
	if got := formatTimestamp(0); got != "" {
		t.Fatalf("格式化零时间戳应为空: %q", got)
	}
}

func TestFileNameAndExtension(t *testing.T) {
	cases := map[string]string{
		"a/b:c?d*e": "a_b_c_d_e",
		"  标题.  ":   "标题",
		"":          "",
	}
	for raw, want := range cases {
		if got := sanitizeFileName(raw); got != want {
			t.Fatalf("sanitizeFileName(%q) = %q, 期望 %q", raw, got, want)
		}
	}
	long := strings.Repeat("字", 200)
	if got := sanitizeFileName(long); len([]rune(got)) != 100 {
		t.Fatalf("过长文件名应被截断: %d", len([]rune(got)))
	}
	if got := mediaExtension("https://x/a/b.mp4?sign=1"); got != ".mp4" {
		t.Fatalf("扩展名解析失败: %q", got)
	}
	if got := mediaExtension("https://x/a/b"); got != ".mp4" {
		t.Fatalf("没有扩展名时应回落 mp4: %q", got)
	}
}

func TestChannelLookup(t *testing.T) {
	if channel, ok := findChannel("新番"); !ok || channel.ID != 24 {
		t.Fatalf("按名字查分区失败: %+v", channel)
	}
	if channel, ok := findChannel("连载新番"); !ok || channel.ID != 11 {
		t.Fatalf("按子分区名查分区失败: %+v", channel)
	}
	if channel, ok := findChannel("24"); !ok || channel.Name != "新番" {
		t.Fatalf("按编号查分区失败: %+v", channel)
	}
	if _, ok := findChannel("不存在"); ok {
		t.Fatal("未知分区不应命中")
	}
	if _, ok := findChannel(""); ok {
		t.Fatal("空分区名不应命中")
	}
	if len(allChannels()) != 13 {
		t.Fatalf("分区总数应为 13, 实际 %d", len(allChannels()))
	}
}

func TestArgumentParsers(t *testing.T) {
	if err := validateOrder("date"); err != nil {
		t.Fatalf("date 应合法: %v", err)
	}
	if err := validateOrder("hot"); err == nil {
		t.Fatal("未知排序应当报错")
	}
	if period, err := parsePeriod("本月"); err != nil || period != 2 {
		t.Fatalf("中文时间维度解析失败: %v %d", err, period)
	}
	if _, err := parsePeriod("昨天"); err == nil {
		t.Fatal("未知时间维度应当报错")
	}
	if month, err := parseSeason("剧场版"); err != nil || month != 99 {
		t.Fatalf("季度解析失败: %v %d", err, month)
	}
	if month, err := parseSeason("10"); err != nil || month != 10 {
		t.Fatalf("数字季度解析失败: %v %d", err, month)
	}
	if _, err := parseSeason("3月"); err == nil {
		t.Fatal("未知季度应当报错")
	}
	if weekday, err := parseWeekday("星期日"); err != nil || weekday != 7 {
		t.Fatalf("星期解析失败: %v %d", err, weekday)
	}
	if _, err := parseWeekday("星期八"); err == nil {
		t.Fatal("未知星期应当报错")
	}
}

// newTestApp 构造使用临时目录与缓冲区输出的命令应用.
func newTestApp(t *testing.T) (*App, *bytes.Buffer, *bytes.Buffer) {
	t.Helper()
	dir := t.TempDir()
	t.Setenv("TUCAO_CONFIG_DIR", filepath.Join(dir, "config"))
	t.Setenv("TUCAO_DATA_DIR", filepath.Join(dir, "data"))
	t.Setenv("OUTPUT", "")
	stdout := &bytes.Buffer{}
	stderr := &bytes.Buffer{}
	app := NewApp()
	app.Out = &output.Writer{Stdout: stdout, Stderr: stderr, DefaultMode: "json"}
	app.Logger = discardLogger()
	return app, stdout, stderr
}

func TestCommandChannelSucceeds(t *testing.T) {
	app, stdout, _ := newTestApp(t)
	if err := app.runForTest(context.Background(), "channel"); err != nil {
		t.Fatalf("channel 应成功: %v", err)
	}
	var payload struct {
		OK   bool `json:"ok"`
		Data struct {
			Channels []Channel `json:"channels"`
		} `json:"data"`
	}
	if err := json.Unmarshal(stdout.Bytes(), &payload); err != nil {
		t.Fatalf("输出不是合法 json: %v", err)
	}
	if !payload.OK || len(payload.Data.Channels) != 3 {
		t.Fatalf("分区输出不正确: %+v", payload)
	}
}

func TestCommandErrorsUseExitCodes(t *testing.T) {
	cases := []struct {
		name string
		args []string
		want int
	}{
		{name: "未知榜单", args: []string{"rank", "--type", "nope"}, want: 2},
		{name: "未知排序", args: []string{"list", "--order", "nope"}, want: 2},
		{name: "未知分区", args: []string{"list", "--channel", "不存在"}, want: 2},
		{name: "缺少参数", args: []string{"video"}, want: 2},
		{name: "未知命令", args: []string{"nope"}, want: 2},
		{name: "缺少分P", args: []string{"video", "danmaku", "100", "--part", "0"}, want: 2},
		{name: "未知导出格式", args: []string{"video", "danmaku", "100", "--format", "srt"}, want: 2},
		{name: "缺少登录", args: []string{"msg"}, want: 3},
		{name: "删除需要确认", args: []string{"fav", "rm", "100"}, want: 4},
	}
	for _, testCase := range cases {
		t.Run(testCase.name, func(t *testing.T) {
			app, _, _ := newTestApp(t)
			err := app.runForTest(context.Background(), testCase.args...)
			if err == nil {
				t.Fatalf("%v 应当失败", testCase.args)
			}
			var exitErr *ExitError
			if !errors.As(err, &exitErr) {
				t.Fatalf("错误应带退出码: %v", err)
			}
			if exitErr.Code != testCase.want {
				t.Fatalf("%v 的退出码为 %d, 期望 %d", testCase.args, exitErr.Code, testCase.want)
			}
		})
	}
}

func TestCommandConfigSetAndGet(t *testing.T) {
	app, stdout, _ := newTestApp(t)
	if err := app.runForTest(context.Background(), "config", "set", "site.host", "tucao.example"); err != nil {
		t.Fatalf("设置配置失败: %v", err)
	}
	stdout.Reset()
	if err := app.runForTest(context.Background(), "config", "get", "site.host"); err != nil {
		t.Fatalf("读取配置失败: %v", err)
	}
	if !strings.Contains(stdout.String(), "tucao.example") {
		t.Fatalf("配置没有生效: %s", stdout.String())
	}
	if err := app.runForTest(context.Background(), "config", "set", "site.host", "不是域名"); err == nil {
		t.Fatal("非法域名应当报错")
	}
	if err := app.runForTest(context.Background(), "config", "set", "unknown.key", "1"); err == nil {
		t.Fatal("未知字段应当报错")
	}
	if err := app.runForTest(context.Background(), "config", "set", "download.threads", "99"); err == nil {
		t.Fatal("越界数值应当报错")
	}
}

func TestReadOnlyBlocksWrites(t *testing.T) {
	app, _, _ := newTestApp(t)
	if err := app.runForTest(context.Background(), "config", "set", "safety.read_only", "true"); err != nil {
		t.Fatalf("设置只读失败: %v", err)
	}
	err := app.runForTest(context.Background(), "video", "danmaku", "send", "100", "内容", "--progress", "10")
	if err == nil {
		t.Fatal("只读模式下写操作应被拒绝")
	}
	var exitErr *ExitError
	if !errors.As(err, &exitErr) || exitErr.Code != 4 {
		t.Fatalf("应为权限拒绝: %v", err)
	}
}

func TestFavoritesAndHistoryCommands(t *testing.T) {
	app, stdout, _ := newTestApp(t)
	if err := app.runForTest(context.Background(), "fav"); err != nil {
		t.Fatalf("空收藏应正常返回: %v", err)
	}
	if !strings.Contains(stdout.String(), "\"total\": 0") {
		t.Fatalf("空收藏输出不正确: %s", stdout.String())
	}
	stdout.Reset()
	if err := app.runForTest(context.Background(), "history"); err != nil {
		t.Fatalf("空历史应正常返回: %v", err)
	}
	if !strings.Contains(stdout.String(), "\"total\": 0") {
		t.Fatalf("空历史输出不正确: %s", stdout.String())
	}
	stdout.Reset()
	if err := app.runForTest(context.Background(), "history", "search", "clear", "--yes"); err != nil {
		t.Fatalf("清空搜索历史失败: %v", err)
	}
}

func TestUsageErrorCarriesUsage(t *testing.T) {
	app, stdout, _ := newTestApp(t)
	if err := app.runForTest(context.Background(), "list", "--order", "nope"); err == nil {
		t.Fatal("应当报错")
	}
	if !strings.Contains(stdout.String(), "invalid_input") {
		t.Fatalf("错误 envelope 应带错误码: %s", stdout.String())
	}
}

func TestHelpAndVersionAreUsable(t *testing.T) {
	app, stdout, _ := newTestApp(t)
	if err := app.runForTest(context.Background(), "--help"); err != nil {
		t.Fatalf("--help 应当成功: %v", err)
	}
	for _, command := range []string{"home", "channel", "week", "list", "rank", "search", "video", "bgm", "article", "space", "msg", "me", "fav", "history", "ad", "update", "config"} {
		if !strings.Contains(stdout.String(), command) {
			t.Fatalf("帮助里缺少命令 %s", command)
		}
	}
}

func TestConfigDirFallbackWhenUnwritable(t *testing.T) {
	dir := t.TempDir()
	blocked := filepath.Join(dir, "blocked")
	if err := os.WriteFile(blocked, []byte("x"), 0o600); err != nil {
		t.Fatalf("准备文件失败: %v", err)
	}
	t.Setenv("TUCAO_CONFIG_DIR", filepath.Join(blocked, "config"))
	t.Setenv("TUCAO_DATA_DIR", filepath.Join(dir, "data"))
	app := NewApp()
	if app.Config.Site.Host == "" {
		t.Fatal("配置目录不可写时应退回默认配置")
	}
	if app.ConfigErr != nil {
		t.Fatalf("写盘失败不应被当成配置错误: %v", app.ConfigErr)
	}
	if app.ConfigWarn == nil {
		t.Fatal("写盘失败应留下警告")
	}
}
