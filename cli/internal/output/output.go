package output

import (
	"encoding/json"
	"fmt"
	"io"
	"os"
	"strings"

	"golang.org/x/term"
	"gopkg.in/yaml.v3"
)

// Mode 是输出格式.
type Mode string

const (
	// ModeRich 是给交互终端看的表格与文字.
	ModeRich Mode = "rich"
	// ModeJSON 是结构化 json.
	ModeJSON Mode = "json"
	// ModeYAML 是结构化 yaml, 非交互场景的默认格式.
	ModeYAML Mode = "yaml"
)

// SchemaVersion 是结构化输出的结构版本, 字段变化时递增.
const SchemaVersion = "1"

// Writer 负责命令输出.
type Writer struct {
	Stdout      io.Writer
	Stderr      io.Writer
	DefaultMode string
	NoTruncate  bool
}

// NewWriter 构造使用标准流的输出器.
func NewWriter() *Writer {
	return &Writer{Stdout: os.Stdout, Stderr: os.Stderr, DefaultMode: "auto"}
}

// Resolve 决定本次命令使用的输出格式.
//
// 显式传入的 --json 与 --yaml 优先级最高, 其次是 OUTPUT 环境变量,
// 再其次是配置里的 output.format; 都为 auto 时按是否交互终端选择.
func (w *Writer) Resolve(asJSON, asYAML bool) (Mode, error) {
	if asJSON && asYAML {
		return ModeRich, fmt.Errorf("不能同时使用 --json 和 --yaml")
	}
	if asJSON {
		return ModeJSON, nil
	}
	if asYAML {
		return ModeYAML, nil
	}
	switch strings.ToLower(w.configuredMode()) {
	case "json":
		return ModeJSON, nil
	case "yaml":
		return ModeYAML, nil
	case "rich":
		return ModeRich, nil
	}
	if !IsTerminal(w.Stdout) {
		return ModeYAML, nil
	}
	return ModeRich, nil
}

// configuredMode 取 OUTPUT 环境变量或配置里的格式.
func (w *Writer) configuredMode() string {
	if value, ok := os.LookupEnv("OUTPUT"); ok && strings.TrimSpace(value) != "" {
		return strings.TrimSpace(value)
	}
	return strings.TrimSpace(w.DefaultMode)
}

// UsesAutoMode 判断当前是否处于 auto 格式.
func (w *Writer) UsesAutoMode() bool {
	mode := strings.ToLower(w.configuredMode())
	return mode == "" || mode == "auto"
}

// Success 包装成功结果.
func Success(data any) map[string]any {
	return map[string]any{"ok": true, "schema_version": SchemaVersion, "data": data}
}

// ErrorPayload 包装失败结果.
func ErrorPayload(code, message string, details any) map[string]any {
	payload := map[string]any{"code": code, "message": message}
	if details != nil {
		payload["details"] = details
	}
	return map[string]any{"ok": false, "schema_version": SchemaVersion, "error": payload}
}

// Emit 输出结构化数据, rich 模式不输出任何内容.
func (w *Writer) Emit(data any, mode Mode) error {
	if mode == ModeRich {
		return nil
	}
	var (
		encoded []byte
		err     error
	)
	if mode == ModeJSON {
		encoded, err = json.MarshalIndent(data, "", "  ")
	} else {
		encoded, err = yaml.Marshal(data)
	}
	if err != nil {
		return err
	}
	_, err = fmt.Fprintln(w.Stdout, string(encoded))
	return err
}

// EmitSuccess 输出成功 envelope.
func (w *Writer) EmitSuccess(data any, mode Mode) error {
	return w.Emit(Success(data), mode)
}

// EmitError 输出失败 envelope, rich 模式写一行到 stderr.
func (w *Writer) EmitError(code, message string, details any, mode Mode) error {
	if mode == ModeRich {
		_, err := fmt.Fprintln(w.Stderr, message)
		return err
	}
	return w.Emit(ErrorPayload(code, message, details), mode)
}

// Line 在 rich 模式下打印一行普通文本.
func (w *Writer) Line(mode Mode, format string, args ...any) {
	if mode != ModeRich {
		return
	}
	fmt.Fprintf(w.Stdout, format+"\n", args...)
}

// RenderTable 输出表格, 非交互时降级为 TSV.
func (w *Writer) RenderTable(mode Mode, title string, headers []string, rows [][]string) {
	if mode != ModeRich {
		return
	}
	RenderTable(w.Stdout, title, headers, rows, TableOptions{
		Interactive: IsTerminal(w.Stdout),
		Width:       TerminalWidth(w.Stdout),
		NoTruncate:  w.NoTruncate,
	})
}

// IsTerminal 判断输出目标是否为字符设备终端.
func IsTerminal(writer io.Writer) bool {
	file, ok := writer.(*os.File)
	if !ok {
		return false
	}
	if strings.EqualFold(os.Getenv("TERM"), "dumb") {
		return false
	}
	return term.IsTerminal(int(file.Fd()))
}

// TerminalWidth 取终端宽度, 取不到时给一个稳妥的默认值.
func TerminalWidth(writer io.Writer) int {
	const fallback = 100
	file, ok := writer.(*os.File)
	if !ok {
		return fallback
	}
	width, _, err := term.GetSize(int(file.Fd()))
	if err != nil || width <= 0 {
		return fallback
	}
	return width
}
