package output

import (
	"bytes"
	"encoding/json"
	"strings"
	"testing"
)

func newTestWriter() (*Writer, *bytes.Buffer, *bytes.Buffer) {
	stdout := &bytes.Buffer{}
	stderr := &bytes.Buffer{}
	return &Writer{Stdout: stdout, Stderr: stderr, DefaultMode: "auto"}, stdout, stderr
}

func TestResolveOutputMode(t *testing.T) {
	writer, _, _ := newTestWriter()
	if mode, err := writer.Resolve(true, false); err != nil || mode != ModeJSON {
		t.Fatalf("--json 应解析为 json: %v %v", mode, err)
	}
	if mode, err := writer.Resolve(false, true); err != nil || mode != ModeYAML {
		t.Fatalf("--yaml 应解析为 yaml: %v %v", mode, err)
	}
	if _, err := writer.Resolve(true, true); err == nil {
		t.Fatal("同时使用 --json 与 --yaml 应当报错")
	}
	// 非交互输出对象默认走 yaml.
	if mode, err := writer.Resolve(false, false); err != nil || mode != ModeYAML {
		t.Fatalf("非交互默认应为 yaml: %v %v", mode, err)
	}
	t.Setenv("OUTPUT", "json")
	if mode, err := writer.Resolve(false, false); err != nil || mode != ModeJSON {
		t.Fatalf("OUTPUT 环境变量应生效: %v %v", mode, err)
	}
	t.Setenv("OUTPUT", "rich")
	if mode, err := writer.Resolve(false, false); err != nil || mode != ModeRich {
		t.Fatalf("OUTPUT 显式指定 rich 应生效: %v %v", mode, err)
	}
}

func TestEmitSuccessEnvelope(t *testing.T) {
	writer, stdout, _ := newTestWriter()
	if err := writer.EmitSuccess(map[string]any{"total": 3}, ModeJSON); err != nil {
		t.Fatalf("输出失败: %v", err)
	}
	var payload struct {
		OK            bool   `json:"ok"`
		SchemaVersion string `json:"schema_version"`
		Data          struct {
			Total int `json:"total"`
		} `json:"data"`
	}
	if err := json.Unmarshal(stdout.Bytes(), &payload); err != nil {
		t.Fatalf("输出不是合法 json: %v", err)
	}
	if !payload.OK || payload.SchemaVersion != SchemaVersion || payload.Data.Total != 3 {
		t.Fatalf("envelope 结构不正确: %+v", payload)
	}
}

func TestEmitErrorEnvelope(t *testing.T) {
	writer, stdout, _ := newTestWriter()
	if err := writer.EmitError("invalid_input", "参数不对", map[string]any{"usage": "tucao list"}, ModeJSON); err != nil {
		t.Fatalf("输出失败: %v", err)
	}
	var payload struct {
		OK    bool `json:"ok"`
		Error struct {
			Code    string         `json:"code"`
			Message string         `json:"message"`
			Details map[string]any `json:"details"`
		} `json:"error"`
	}
	if err := json.Unmarshal(stdout.Bytes(), &payload); err != nil {
		t.Fatalf("输出不是合法 json: %v", err)
	}
	if payload.OK || payload.Error.Code != "invalid_input" || payload.Error.Message != "参数不对" {
		t.Fatalf("错误 envelope 不正确: %+v", payload)
	}
	if payload.Error.Details["usage"] != "tucao list" {
		t.Fatalf("错误详情缺失: %+v", payload.Error.Details)
	}
}

func TestEmitErrorRichGoesToStderr(t *testing.T) {
	writer, stdout, stderr := newTestWriter()
	if err := writer.EmitError("upstream_error", "站点挂了", nil, ModeRich); err != nil {
		t.Fatalf("输出失败: %v", err)
	}
	if stdout.Len() != 0 {
		t.Fatalf("rich 模式不应写 stdout: %q", stdout.String())
	}
	if !strings.Contains(stderr.String(), "站点挂了") {
		t.Fatalf("错误应写到 stderr: %q", stderr.String())
	}
}

func TestRenderTableNonInteractiveIsTSV(t *testing.T) {
	buffer := &bytes.Buffer{}
	RenderTable(buffer, "标题行", []string{"编号", "标题"}, [][]string{{"1001", "视频\t标题"}}, TableOptions{Interactive: false})
	lines := strings.Split(strings.TrimSpace(buffer.String()), "\n")
	if len(lines) != 2 {
		t.Fatalf("应有表头与一行数据: %q", buffer.String())
	}
	if lines[0] != "编号\t标题" {
		t.Fatalf("表头应为 TSV: %q", lines[0])
	}
	if lines[1] != "1001\t视频 标题" {
		t.Fatalf("数据行应去掉制表符: %q", lines[1])
	}
}

func TestRenderTableTruncatesToWidth(t *testing.T) {
	buffer := &bytes.Buffer{}
	RenderTable(buffer, "", []string{"标题"}, [][]string{
		{"这是一条很长的标题需要被截断处理"},
	}, TableOptions{Interactive: true, Width: 20})
	out := buffer.String()
	for _, line := range strings.Split(strings.TrimSpace(out), "\n") {
		if len([]rune(line)) > 20 {
			t.Fatalf("行宽超出限制: %q", line)
		}
	}
	if !strings.Contains(out, "...") {
		t.Fatalf("超宽内容应被截断: %q", out)
	}
}

func TestRenderTableNoTruncate(t *testing.T) {
	buffer := &bytes.Buffer{}
	RenderTable(buffer, "", []string{"标题"}, [][]string{{"这是一条很长的标题"}}, TableOptions{
		Interactive: true,
		Width:       10,
		NoTruncate:  true,
	})
	if !strings.Contains(buffer.String(), "这是一条很长的标题") {
		t.Fatalf("关闭截断后应保留完整内容: %q", buffer.String())
	}
}

func TestRenderTableAlignsCJKWidth(t *testing.T) {
	buffer := &bytes.Buffer{}
	RenderTable(buffer, "", []string{"名称"}, [][]string{{"短"}, {"很长很长"}}, TableOptions{Interactive: true, Width: 80})
	lines := strings.Split(strings.TrimSpace(buffer.String()), "\n")
	if len(lines) != 4 {
		t.Fatalf("应有表头, 分隔线与两行数据: %q", buffer.String())
	}
	if !strings.Contains(lines[2], "短") || !strings.Contains(lines[3], "很长很长") {
		t.Fatalf("表格内容不正确: %q", buffer.String())
	}
}
