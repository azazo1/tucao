package paths

import (
	"os"
	"path/filepath"
	"strings"
)

// 配置与数据目录的定位.
//
// 默认遵循 XDG: 配置在 ~/.config/tucao, 本地数据在 ~/.local/share/tucao.
// 两个目录都可以用环境变量覆盖, 便于测试与多账号隔离.

// ConfigDir 返回配置目录.
func ConfigDir() string {
	if dir := strings.TrimSpace(os.Getenv("TUCAO_CONFIG_DIR")); dir != "" {
		return dir
	}
	return filepath.Join(xdgBase("XDG_CONFIG_HOME", ".config"), "tucao")
}

// DataDir 返回本地数据目录.
func DataDir() string {
	if dir := strings.TrimSpace(os.Getenv("TUCAO_DATA_DIR")); dir != "" {
		return dir
	}
	return filepath.Join(xdgBase("XDG_DATA_HOME", filepath.Join(".local", "share")), "tucao")
}

// ConfigFile 是 config.toml 的路径.
func ConfigFile() string { return filepath.Join(ConfigDir(), "config.toml") }

// AuthFile 是 auth.json 的路径.
func AuthFile() string { return filepath.Join(ConfigDir(), "auth.json") }

func xdgBase(env, fallback string) string {
	if base := strings.TrimSpace(os.Getenv(env)); base != "" {
		return base
	}
	home, err := os.UserHomeDir()
	if err != nil || home == "" {
		return fallback
	}
	return filepath.Join(home, fallback)
}
