package config

import (
	"errors"
	"fmt"
	"os"
	"strings"

	"github.com/pelletier/go-toml/v2"

	"github.com/azazo1/tucao/cli/internal/model"
	"github.com/azazo1/tucao/cli/internal/paths"
)

// CurrentVersion 是当前配置结构版本, 结构变更时递增并补充迁移逻辑.
const CurrentVersion = 1

// ErrParse 表示配置文件存在但无法解析, 属于需要用户处理的问题;
// 写盘失败 (例如目录只读) 不属于这个错误, 调用方可以退回默认配置继续跑.
var ErrParse = errors.New("解析 config.toml 失败")

// DefaultTOML 是首次生成的配置内容, 注释与字段说明保持一致.
const DefaultTOML = `# 吐槽弹幕网 CLI settings.
version = 1

[output]
# auto, rich, json, yaml.
format = "auto"
# 表格在交互终端里是否按终端宽度截断.
truncate = true

[network]
# 单次请求超时, 单位秒.
timeout_seconds = 30
# 只读请求的重试次数, 写操作不重试.
retries = 1

[site]
# 站点域名, 站点更换域名时改这里.
host = "www.tucao.my"

[download]
# 多分P下载的并发数.
threads = 4
# 默认输出目录, 留空表示当前目录.
output_dir = ""
# 目标文件已存在时是否覆盖.
overwrite = false

[danmaku]
# 导出 ass 时使用的字体.
font = "sans-serif"
font_size = 25
# 滚动弹幕在屏幕上停留的秒数.
duration_seconds = 8
# 固定弹幕停留的秒数.
static_duration_seconds = 5
# 弹幕显示区域占画面高度的比例.
area = 1.0
opacity = 1.0
stroke_width = 1.5
line_height = 1.6
hide_scroll = false
hide_top = false
hide_bottom = false

[history]
# 本地播放历史的条数上限.
limit = 500

[search]
# 本地搜索历史的条数上限.
history_limit = 20

[safety]
# 拒绝全部账号侧写操作, 只读查询与下载仍可用.
read_only = false
# 允许新增类写操作, 拒绝删除与清空类操作.
non_destructive = false
# 删除与清空类操作需要显式确认.
confirm_dangerous_actions = true
`

// Config 是 config.toml 的结构.
type Config struct {
	Version  int            `toml:"version" json:"version" yaml:"version"`
	Output   OutputConfig   `toml:"output" json:"output" yaml:"output"`
	Network  NetworkConfig  `toml:"network" json:"network" yaml:"network"`
	Site     SiteConfig     `toml:"site" json:"site" yaml:"site"`
	Download DownloadConfig `toml:"download" json:"download" yaml:"download"`
	Danmaku  DanmakuConfig  `toml:"danmaku" json:"danmaku" yaml:"danmaku"`
	History  HistoryConfig  `toml:"history" json:"history" yaml:"history"`
	Search   SearchConfig   `toml:"search" json:"search" yaml:"search"`
	Safety   SafetyConfig   `toml:"safety" json:"safety" yaml:"safety"`
}

// OutputConfig 控制终端与结构化输出.
type OutputConfig struct {
	Format   string `toml:"format" json:"format" yaml:"format"`
	Truncate bool   `toml:"truncate" json:"truncate" yaml:"truncate"`
}

// NetworkConfig 控制请求超时与重试.
type NetworkConfig struct {
	TimeoutSeconds int `toml:"timeout_seconds" json:"timeout_seconds" yaml:"timeout_seconds"`
	Retries        int `toml:"retries" json:"retries" yaml:"retries"`
}

// SiteConfig 保存站点域名.
type SiteConfig struct {
	Host string `toml:"host" json:"host" yaml:"host"`
}

// DownloadConfig 控制离线下载.
type DownloadConfig struct {
	Threads   int    `toml:"threads" json:"threads" yaml:"threads"`
	OutputDir string `toml:"output_dir" json:"output_dir" yaml:"output_dir"`
	Overwrite bool   `toml:"overwrite" json:"overwrite" yaml:"overwrite"`
}

// DanmakuConfig 是弹幕导出的排版参数.
type DanmakuConfig struct {
	Font                  string  `toml:"font" json:"font" yaml:"font"`
	FontSize              int     `toml:"font_size" json:"font_size" yaml:"font_size"`
	DurationSeconds       float64 `toml:"duration_seconds" json:"duration_seconds" yaml:"duration_seconds"`
	StaticDurationSeconds float64 `toml:"static_duration_seconds" json:"static_duration_seconds" yaml:"static_duration_seconds"`
	Area                  float64 `toml:"area" json:"area" yaml:"area"`
	Opacity               float64 `toml:"opacity" json:"opacity" yaml:"opacity"`
	StrokeWidth           float64 `toml:"stroke_width" json:"stroke_width" yaml:"stroke_width"`
	LineHeight            float64 `toml:"line_height" json:"line_height" yaml:"line_height"`
	HideScroll            bool    `toml:"hide_scroll" json:"hide_scroll" yaml:"hide_scroll"`
	HideTop               bool    `toml:"hide_top" json:"hide_top" yaml:"hide_top"`
	HideBottom            bool    `toml:"hide_bottom" json:"hide_bottom" yaml:"hide_bottom"`
}

// HistoryConfig 控制本地播放历史.
type HistoryConfig struct {
	Limit int `toml:"limit" json:"limit" yaml:"limit"`
}

// SearchConfig 控制本地搜索历史.
type SearchConfig struct {
	HistoryLimit int `toml:"history_limit" json:"history_limit" yaml:"history_limit"`
}

// SafetyConfig 是写操作开关.
type SafetyConfig struct {
	ReadOnly                bool `toml:"read_only" json:"read_only" yaml:"read_only"`
	NonDestructive          bool `toml:"non_destructive" json:"non_destructive" yaml:"non_destructive"`
	ConfirmDangerousActions bool `toml:"confirm_dangerous_actions" json:"confirm_dangerous_actions" yaml:"confirm_dangerous_actions"`
}

// Default 返回带全部默认值的配置.
func Default() Config {
	return Config{
		Version: CurrentVersion,
		Output:  OutputConfig{Format: "auto", Truncate: true},
		Network: NetworkConfig{TimeoutSeconds: 30, Retries: 1},
		Site:    SiteConfig{Host: model.DefaultHost},
		Download: DownloadConfig{
			Threads: 4,
		},
		Danmaku: DanmakuConfig{
			Font:                  "sans-serif",
			FontSize:              25,
			DurationSeconds:       8,
			StaticDurationSeconds: 5,
			Area:                  1,
			Opacity:               1,
			StrokeWidth:           1.5,
			LineHeight:            1.6,
		},
		History: HistoryConfig{Limit: 500},
		Search:  SearchConfig{HistoryLimit: 20},
		Safety:  SafetyConfig{ConfirmDangerousActions: true},
	}
}

// BaseURL 是当前站点地址, 末尾带斜杠.
func (c Config) BaseURL() string {
	return "https://" + c.Site.Host + "/"
}

// Store 负责配置文件的位置与读写.
type Store struct {
	Dir  string
	File string
}

// NewStore 定位配置文件.
func NewStore() *Store {
	return &Store{Dir: paths.ConfigDir(), File: paths.ConfigFile()}
}

// Load 读取配置, 文件不存在时返回默认配置.
func (s *Store) Load() (Config, error) {
	data, err := os.ReadFile(s.File)
	if errors.Is(err, os.ErrNotExist) {
		return Default(), nil
	}
	if err != nil {
		return Config{}, fmt.Errorf("读取配置失败: %w", err)
	}
	config, _, err := decode(data)
	if err != nil {
		return Config{}, err
	}
	return config, nil
}

// Exists 判断配置文件是否存在.
func (s *Store) Exists() bool {
	_, err := os.Stat(s.File)
	return err == nil
}

// Ensure 读取配置, 缺失时写入默认文件, 需要迁移时自动回写.
func (s *Store) Ensure() (Config, error) {
	data, err := os.ReadFile(s.File)
	if errors.Is(err, os.ErrNotExist) {
		config := Default()
		if err := s.write([]byte(DefaultTOML)); err != nil {
			return Config{}, err
		}
		return config, nil
	}
	if err != nil {
		return Config{}, fmt.Errorf("读取配置失败: %w", err)
	}
	config, migrated, err := decode(data)
	if err != nil {
		return Config{}, err
	}
	if migrated {
		if err := s.Save(config); err != nil {
			return Config{}, err
		}
	}
	return config, nil
}

// Save 校验后写回配置文件.
func (s *Store) Save(config Config) error {
	if config.Version == 0 {
		config.Version = CurrentVersion
	}
	normalized, _, err := validate(config)
	if err != nil {
		return err
	}
	data, err := toml.Marshal(normalized)
	if err != nil {
		return fmt.Errorf("编码配置失败: %w", err)
	}
	return s.write(data)
}

// WriteDefault 写入带注释的默认配置, 已有文件时由调用方决定是否覆盖.
func (s *Store) WriteDefault() error {
	return s.write([]byte(DefaultTOML))
}

func (s *Store) write(data []byte) error {
	if err := os.MkdirAll(s.Dir, 0o700); err != nil {
		return fmt.Errorf("创建配置目录失败: %w", err)
	}
	temporary, err := os.CreateTemp(s.Dir, ".config-*.toml")
	if err != nil {
		return fmt.Errorf("创建临时配置失败: %w", err)
	}
	name := temporary.Name()
	defer os.Remove(name)
	if err := temporary.Chmod(0o600); err != nil {
		temporary.Close()
		return fmt.Errorf("设置配置权限失败: %w", err)
	}
	if _, err := temporary.Write(data); err != nil {
		temporary.Close()
		return fmt.Errorf("写入配置失败: %w", err)
	}
	if err := temporary.Sync(); err != nil {
		temporary.Close()
		return fmt.Errorf("同步配置失败: %w", err)
	}
	if err := temporary.Close(); err != nil {
		return fmt.Errorf("关闭临时配置失败: %w", err)
	}
	if err := os.Rename(name, s.File); err != nil {
		return fmt.Errorf("替换配置失败: %w", err)
	}
	return nil
}

func decode(data []byte) (Config, bool, error) {
	var version struct {
		Version int `toml:"version"`
	}
	if err := toml.Unmarshal(data, &version); err != nil {
		return Config{}, false, fmt.Errorf("%w: %v", ErrParse, err)
	}
	config := Default()
	if err := toml.Unmarshal(data, &config); err != nil {
		return Config{}, false, fmt.Errorf("%w: %v", ErrParse, err)
	}
	config, migrated, err := migrate(config, version.Version)
	if err != nil {
		return Config{}, false, err
	}
	normalized, changed, err := validate(config)
	if err != nil {
		return Config{}, false, err
	}
	return normalized, migrated || changed, nil
}

func validate(config Config) (Config, bool, error) {
	changed := false
	format := strings.ToLower(strings.TrimSpace(config.Output.Format))
	if format == "" {
		format = Default().Output.Format
		changed = true
	}
	switch format {
	case "auto", "rich", "json", "yaml":
		config.Output.Format = format
	default:
		return Config{}, false, fmt.Errorf("output.format 不支持: %s", config.Output.Format)
	}

	if config.Network.TimeoutSeconds == 0 {
		config.Network.TimeoutSeconds = Default().Network.TimeoutSeconds
		changed = true
	}
	if config.Network.TimeoutSeconds < 1 || config.Network.TimeoutSeconds > 300 {
		return Config{}, false, fmt.Errorf("network.timeout_seconds 必须在 1 到 300 之间")
	}
	if config.Network.Retries < 0 || config.Network.Retries > 5 {
		return Config{}, false, fmt.Errorf("network.retries 必须在 0 到 5 之间")
	}

	host, ok := model.NormalizeHost(config.Site.Host)
	if !ok {
		return Config{}, false, fmt.Errorf("site.host 不是合法的站点域名: %s", config.Site.Host)
	}
	if host != config.Site.Host {
		config.Site.Host = host
		changed = true
	}

	if config.Download.Threads == 0 {
		config.Download.Threads = Default().Download.Threads
		changed = true
	}
	if config.Download.Threads < 1 || config.Download.Threads > 32 {
		return Config{}, false, fmt.Errorf("download.threads 必须在 1 到 32 之间")
	}
	outputDir := strings.TrimSpace(config.Download.OutputDir)
	if outputDir != config.Download.OutputDir {
		config.Download.OutputDir = outputDir
		changed = true
	}

	font := strings.TrimSpace(config.Danmaku.Font)
	if font == "" {
		font = Default().Danmaku.Font
		changed = true
	}
	if font != config.Danmaku.Font {
		config.Danmaku.Font = font
		changed = true
	}
	if config.Danmaku.FontSize == 0 {
		config.Danmaku.FontSize = Default().Danmaku.FontSize
		changed = true
	}
	if config.Danmaku.FontSize < 8 || config.Danmaku.FontSize > 64 {
		return Config{}, false, fmt.Errorf("danmaku.font_size 必须在 8 到 64 之间")
	}
	if err := checkRange("danmaku.duration_seconds", config.Danmaku.DurationSeconds, 1, 30); err != nil {
		return Config{}, false, err
	}
	if err := checkRange("danmaku.static_duration_seconds", config.Danmaku.StaticDurationSeconds, 1, 30); err != nil {
		return Config{}, false, err
	}
	if err := checkRange("danmaku.area", config.Danmaku.Area, 0.1, 1); err != nil {
		return Config{}, false, err
	}
	if err := checkRange("danmaku.opacity", config.Danmaku.Opacity, 0, 1); err != nil {
		return Config{}, false, err
	}
	if err := checkRange("danmaku.stroke_width", config.Danmaku.StrokeWidth, 0, 5); err != nil {
		return Config{}, false, err
	}
	if err := checkRange("danmaku.line_height", config.Danmaku.LineHeight, 1, 3); err != nil {
		return Config{}, false, err
	}

	if config.History.Limit == 0 {
		config.History.Limit = Default().History.Limit
		changed = true
	}
	if config.History.Limit < 1 || config.History.Limit > 10000 {
		return Config{}, false, fmt.Errorf("history.limit 必须在 1 到 10000 之间")
	}
	if config.Search.HistoryLimit < 0 || config.Search.HistoryLimit > 500 {
		return Config{}, false, fmt.Errorf("search.history_limit 必须在 0 到 500 之间")
	}
	return config, changed, nil
}

func checkRange(name string, value, min, max float64) error {
	if value < min || value > max {
		return fmt.Errorf("%s 必须在 %g 到 %g 之间", name, min, max)
	}
	return nil
}
