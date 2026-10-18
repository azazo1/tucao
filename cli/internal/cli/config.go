package cli

import (
	"fmt"
	"os"
	"sort"
	"strconv"
	"strings"

	"github.com/pelletier/go-toml/v2"
	"github.com/spf13/cobra"

	"github.com/azazo1/tucao/cli/internal/api"
	"github.com/azazo1/tucao/cli/internal/config"
	"github.com/azazo1/tucao/cli/internal/output"
)

// fieldSpec 描述一个可读写的配置字段.
type fieldSpec struct {
	Key         string
	Kind        string
	Description string
	Read        func(config.Config) any
	Write       func(*config.Config, string) error
}

func newField(key, kind, description string, read func(config.Config) any, assign func(*config.Config, any)) fieldSpec {
	return fieldSpec{
		Key:         key,
		Kind:        kind,
		Description: description,
		Read:        read,
		Write: func(target *config.Config, raw string) error {
			value, err := convertValue(kind, raw)
			if err != nil {
				return fmt.Errorf("%s 的值不合法: %s", key, raw)
			}
			assign(target, value)
			return nil
		},
	}
}

func convertValue(kind, raw string) (any, error) {
	text := strings.TrimSpace(raw)
	switch kind {
	case "string":
		return text, nil
	case "bool":
		switch strings.ToLower(text) {
		case "true", "1", "yes", "on":
			return true, nil
		case "false", "0", "no", "off":
			return false, nil
		}
		return nil, fmt.Errorf("需要布尔值")
	case "int":
		return strconv.Atoi(text)
	case "float":
		return strconv.ParseFloat(text, 64)
	default:
		return nil, fmt.Errorf("不支持的字段类型 %s", kind)
	}
}

// configFields 是全部可读写的配置字段.
func configFields() []fieldSpec {
	return []fieldSpec{
		newField("output.format", "string", "输出格式: auto, rich, json, yaml",
			func(c config.Config) any { return c.Output.Format },
			func(c *config.Config, value any) { c.Output.Format = value.(string) }),
		newField("output.truncate", "bool", "表格是否按终端宽度截断",
			func(c config.Config) any { return c.Output.Truncate },
			func(c *config.Config, value any) { c.Output.Truncate = value.(bool) }),
		newField("network.timeout_seconds", "int", "单次请求超时, 单位秒",
			func(c config.Config) any { return c.Network.TimeoutSeconds },
			func(c *config.Config, value any) { c.Network.TimeoutSeconds = value.(int) }),
		newField("network.retries", "int", "只读请求的重试次数",
			func(c config.Config) any { return c.Network.Retries },
			func(c *config.Config, value any) { c.Network.Retries = value.(int) }),
		newField("site.host", "string", "站点域名",
			func(c config.Config) any { return c.Site.Host },
			func(c *config.Config, value any) { c.Site.Host = value.(string) }),
		newField("download.threads", "int", "媒体下载并发数",
			func(c config.Config) any { return c.Download.Threads },
			func(c *config.Config, value any) { c.Download.Threads = value.(int) }),
		newField("download.output_dir", "string", "默认下载目录, 留空表示当前目录",
			func(c config.Config) any { return c.Download.OutputDir },
			func(c *config.Config, value any) { c.Download.OutputDir = value.(string) }),
		newField("download.overwrite", "bool", "目标文件已存在时是否覆盖",
			func(c config.Config) any { return c.Download.Overwrite },
			func(c *config.Config, value any) { c.Download.Overwrite = value.(bool) }),
		newField("danmaku.font", "string", "弹幕导出使用的字体",
			func(c config.Config) any { return c.Danmaku.Font },
			func(c *config.Config, value any) { c.Danmaku.Font = value.(string) }),
		newField("danmaku.font_size", "int", "弹幕字号",
			func(c config.Config) any { return c.Danmaku.FontSize },
			func(c *config.Config, value any) { c.Danmaku.FontSize = value.(int) }),
		newField("danmaku.duration_seconds", "float", "滚动弹幕停留秒数",
			func(c config.Config) any { return c.Danmaku.DurationSeconds },
			func(c *config.Config, value any) { c.Danmaku.DurationSeconds = value.(float64) }),
		newField("danmaku.static_duration_seconds", "float", "固定弹幕停留秒数",
			func(c config.Config) any { return c.Danmaku.StaticDurationSeconds },
			func(c *config.Config, value any) { c.Danmaku.StaticDurationSeconds = value.(float64) }),
		newField("danmaku.area", "float", "弹幕显示区域占画面高度的比例",
			func(c config.Config) any { return c.Danmaku.Area },
			func(c *config.Config, value any) { c.Danmaku.Area = value.(float64) }),
		newField("danmaku.opacity", "float", "弹幕不透明度",
			func(c config.Config) any { return c.Danmaku.Opacity },
			func(c *config.Config, value any) { c.Danmaku.Opacity = value.(float64) }),
		newField("danmaku.stroke_width", "float", "弹幕描边宽度",
			func(c config.Config) any { return c.Danmaku.StrokeWidth },
			func(c *config.Config, value any) { c.Danmaku.StrokeWidth = value.(float64) }),
		newField("danmaku.line_height", "float", "弹幕行高倍数",
			func(c config.Config) any { return c.Danmaku.LineHeight },
			func(c *config.Config, value any) { c.Danmaku.LineHeight = value.(float64) }),
		newField("danmaku.hide_scroll", "bool", "导出时去掉滚动弹幕",
			func(c config.Config) any { return c.Danmaku.HideScroll },
			func(c *config.Config, value any) { c.Danmaku.HideScroll = value.(bool) }),
		newField("danmaku.hide_top", "bool", "导出时去掉顶部弹幕",
			func(c config.Config) any { return c.Danmaku.HideTop },
			func(c *config.Config, value any) { c.Danmaku.HideTop = value.(bool) }),
		newField("danmaku.hide_bottom", "bool", "导出时去掉底部弹幕",
			func(c config.Config) any { return c.Danmaku.HideBottom },
			func(c *config.Config, value any) { c.Danmaku.HideBottom = value.(bool) }),
		newField("history.limit", "int", "本地播放历史条数上限",
			func(c config.Config) any { return c.History.Limit },
			func(c *config.Config, value any) { c.History.Limit = value.(int) }),
		newField("search.history_limit", "int", "本地搜索历史条数上限",
			func(c config.Config) any { return c.Search.HistoryLimit },
			func(c *config.Config, value any) { c.Search.HistoryLimit = value.(int) }),
		newField("safety.read_only", "bool", "拒绝全部账号侧写操作",
			func(c config.Config) any { return c.Safety.ReadOnly },
			func(c *config.Config, value any) { c.Safety.ReadOnly = value.(bool) }),
		newField("safety.non_destructive", "bool", "拒绝删除与清空类操作",
			func(c config.Config) any { return c.Safety.NonDestructive },
			func(c *config.Config, value any) { c.Safety.NonDestructive = value.(bool) }),
		newField("safety.confirm_dangerous_actions", "bool", "删除与清空类操作需要 --yes",
			func(c config.Config) any { return c.Safety.ConfirmDangerousActions },
			func(c *config.Config, value any) { c.Safety.ConfirmDangerousActions = value.(bool) }),
	}
}

func findField(key string) (fieldSpec, bool) {
	normalized := strings.ToLower(strings.TrimSpace(key))
	for _, field := range configFields() {
		if field.Key == normalized {
			return field, true
		}
	}
	return fieldSpec{}, false
}

func (a *App) newConfigCommand() *cobra.Command {
	command := &cobra.Command{
		Use:   "config",
		Short: "查看与修改 CLI 配置",
		Long: `查看与修改 CLI 配置.

配置文件默认位于 ~/.config/tucao/config.toml, 可以用 TUCAO_CONFIG_DIR 覆盖目录.`,
		Args: cobra.NoArgs,
		RunE: func(command *cobra.Command, _ []string) error {
			return a.runConfigStatus(command)
		},
	}
	command.AddCommand(a.newConfigInitCommand(), a.newConfigStatusCommand(),
		a.newConfigGetCommand(), a.newConfigSetCommand(), a.newConfigUpgradeCommand())
	return command
}

func (a *App) newConfigInitCommand() *cobra.Command {
	var force bool
	command := &cobra.Command{
		Use:   "init",
		Short: "创建默认配置文件",
		Args:  cobra.NoArgs,
		RunE: func(command *cobra.Command, _ []string) error {
			if a.ConfigStore.Exists() && !force {
				return a.invalidInput(command, "配置文件已存在: "+a.ConfigStore.File+" , 如需覆盖请加 --force")
			}
			if err := a.ConfigStore.WriteDefault(); err != nil {
				return a.fail(command, api.WrapError(api.CodeInternal, "写入配置", err.Error(), err), "")
			}
			reloaded, err := a.ConfigStore.Load()
			if err != nil {
				return a.fail(command, api.WrapError(api.CodeInternal, "读取配置", err.Error(), err), "")
			}
			a.Config = reloaded
			return a.finish(command, map[string]any{
				"path":    a.ConfigStore.File,
				"version": reloaded.Version,
				"created": true,
			}, func(mode output.Mode) {
				a.Out.Line(mode, "已写入默认配置: %s", a.ConfigStore.File)
			})
		},
	}
	command.Flags().BoolVar(&force, "force", false, "覆盖已存在的配置文件")
	return command
}

func (a *App) newConfigStatusCommand() *cobra.Command {
	return &cobra.Command{
		Use:   "status",
		Short: "显示配置文件位置与各字段状态",
		Args:  cobra.NoArgs,
		RunE: func(command *cobra.Command, _ []string) error {
			return a.runConfigStatus(command)
		},
	}
}

// configFieldStatus 是 status 输出里的一个字段.
type configFieldStatus struct {
	Key         string `json:"key" yaml:"key"`
	Value       any    `json:"value" yaml:"value"`
	State       string `json:"state" yaml:"state"`
	Description string `json:"description,omitempty" yaml:"description,omitempty"`
}

func (a *App) runConfigStatus(command *cobra.Command) error {
	status := map[string]any{
		"path":     a.ConfigStore.File,
		"data_dir": a.dataDirPath(),
		"exists":   a.ConfigStore.Exists(),
		"version":  a.Config.Version,
	}
	states := make([]configFieldStatus, 0, len(configFields()))
	raw, present := readRawConfig(a.ConfigStore.File)
	for _, field := range configFields() {
		state := "missing"
		if _, ok := rawPath(raw, field.Key); ok {
			state = "set"
		}
		states = append(states, configFieldStatus{
			Key:         field.Key,
			Value:       field.Read(a.Config),
			State:       state,
			Description: field.Description,
		})
	}
	status["fields"] = states
	if a.ConfigErr != nil {
		status["error"] = a.ConfigErr.Error()
	}
	sort.Slice(states, func(left, right int) bool { return states[left].Key < states[right].Key })
	_ = present
	return a.finish(command, status, func(mode output.Mode) {
		a.Out.Line(mode, "配置文件: %s", a.ConfigStore.File)
		a.Out.Line(mode, "数据目录: %s", a.dataDirPath())
		if a.ConfigErr != nil {
			a.Out.Line(mode, "配置错误: %v", a.ConfigErr)
		}
		rows := make([][]string, 0, len(states))
		for _, field := range states {
			rows = append(rows, []string{field.Key, formatValue(field.Value), field.State})
		}
		a.Out.RenderTable(mode, "配置字段", []string{"字段", "当前值", "来源"}, rows)
	})
}

func (a *App) newConfigGetCommand() *cobra.Command {
	return &cobra.Command{
		Use:   "get [字段]",
		Short: "读取配置字段",
		Long: `读取配置字段.

不带字段名时输出整份生效配置, 字段名用点号分隔, 例如 site.host.`,
		Args: cobra.MaximumNArgs(1),
		RunE: func(command *cobra.Command, args []string) error {
			if len(args) == 0 {
				return a.finish(command, a.Config, nil)
			}
			field, ok := findField(args[0])
			if !ok {
				return a.invalidInput(command, "未知配置字段: "+args[0])
			}
			value := field.Read(a.Config)
			return a.finish(command, map[string]any{"key": field.Key, "value": value}, func(mode output.Mode) {
				a.Out.Line(mode, "%s = %s", field.Key, formatValue(value))
			})
		},
	}
}

func (a *App) newConfigSetCommand() *cobra.Command {
	return &cobra.Command{
		Use:   "set 字段 值",
		Short: "修改配置字段",
		Long: `修改配置字段并写回 config.toml.

字段名用点号分隔, 例如 tucao config set site.host www.tucao.my.`,
		Args: cobra.ExactArgs(2),
		RunE: func(command *cobra.Command, args []string) error {
			field, ok := findField(args[0])
			if !ok {
				return a.invalidInput(command, "未知配置字段: "+args[0])
			}
			target := a.Config
			if err := field.Write(&target, args[1]); err != nil {
				return a.invalidInput(command, err.Error())
			}
			if err := a.ConfigStore.Save(target); err != nil {
				return a.fail(command, api.WrapError(api.CodeInvalidInput, "保存配置", err.Error(), err), "")
			}
			reloaded, err := a.ConfigStore.Load()
			if err != nil {
				return a.fail(command, api.WrapError(api.CodeInternal, "读取配置", err.Error(), err), "")
			}
			a.Config = reloaded
			value := field.Read(a.Config)
			return a.finish(command, map[string]any{"key": field.Key, "value": value}, func(mode output.Mode) {
				a.Out.Line(mode, "已更新 %s = %s", field.Key, formatValue(value))
			})
		},
	}
}

func (a *App) newConfigUpgradeCommand() *cobra.Command {
	return &cobra.Command{
		Use:   "upgrade",
		Short: "把已有配置补齐到当前格式",
		Args:  cobra.NoArgs,
		RunE: func(command *cobra.Command, _ []string) error {
			before := a.Config.Version
			upgraded, err := a.ConfigStore.Ensure()
			if err != nil {
				return a.fail(command, api.WrapError(api.CodeInvalidInput, "升级配置", err.Error(), err), "")
			}
			if err := a.ConfigStore.Save(upgraded); err != nil {
				return a.fail(command, api.WrapError(api.CodeInternal, "保存配置", err.Error(), err), "")
			}
			reloaded, err := a.ConfigStore.Load()
			if err != nil {
				return a.fail(command, api.WrapError(api.CodeInternal, "读取配置", err.Error(), err), "")
			}
			a.Config = reloaded
			return a.finish(command, map[string]any{
				"path":            a.ConfigStore.File,
				"version_before":  before,
				"version_current": reloaded.Version,
			}, func(mode output.Mode) {
				a.Out.Line(mode, "配置已升级到版本 %d: %s", reloaded.Version, a.ConfigStore.File)
			})
		},
	}
}

func (a *App) dataDirPath() string {
	dataStore, err := a.dataOrErr()
	if err != nil {
		return ""
	}
	return dataStore.Dir
}

// readRawConfig 读取原始配置内容, 用于判断字段是否被显式写过.
func readRawConfig(path string) (map[string]any, bool) {
	data, err := os.ReadFile(path)
	if err != nil {
		return map[string]any{}, false
	}
	var raw map[string]any
	if err := toml.Unmarshal(data, &raw); err != nil {
		return map[string]any{}, false
	}
	return raw, true
}

func rawPath(raw map[string]any, key string) (any, bool) {
	var current any = raw
	for _, part := range strings.Split(key, ".") {
		values, ok := current.(map[string]any)
		if !ok {
			return nil, false
		}
		value, exists := values[part]
		if !exists {
			return nil, false
		}
		current = value
	}
	return current, true
}

func formatValue(value any) string {
	switch typed := value.(type) {
	case nil:
		return ""
	case string:
		return typed
	case bool:
		return strconv.FormatBool(typed)
	case int:
		return strconv.Itoa(typed)
	case float64:
		return strconv.FormatFloat(typed, 'f', -1, 64)
	default:
		return fmt.Sprintf("%v", typed)
	}
}
