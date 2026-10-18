package store

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"

	"github.com/azazo1/tucao/cli/internal/paths"
)

// 本地数据文件名.
const (
	// FavoritesFile 保存本地收藏.
	FavoritesFile = "favorites.json"
	// HistoryFile 保存本地播放历史.
	HistoryFile = "history.json"
	// SearchHistoryFile 保存本地搜索历史.
	SearchHistoryFile = "search_history.json"
)

// Store 负责本地数据文件的读写.
//
// 数据与配置分开存放: 配置在 ~/.config/tucao, 收藏与历史在
// ~/.local/share/tucao, 这样删除配置不会带走用户数据.
type Store struct {
	Dir string
}

// NewStore 定位数据目录.
func NewStore() *Store {
	return &Store{Dir: paths.DataDir()}
}

// Path 返回数据文件的完整路径.
func (s *Store) Path(name string) string {
	return filepath.Join(s.Dir, name)
}

// ReadJSON 读取 json 数据文件.
//
// 返回的 bool 表示文件是否存在, 不存在时 target 不会被改动,
// 调用方据此决定使用默认空数据.
func (s *Store) ReadJSON(name string, target any) (bool, error) {
	data, err := os.ReadFile(s.Path(name))
	if errors.Is(err, os.ErrNotExist) {
		return false, nil
	}
	if err != nil {
		return false, fmt.Errorf("读取 %s 失败: %w", name, err)
	}
	if err := json.Unmarshal(data, target); err != nil {
		return true, fmt.Errorf("解析 %s 失败: %w", name, err)
	}
	return true, nil
}

// WriteJSON 原子写入 json 数据文件.
func (s *Store) WriteJSON(name string, value any) error {
	data, err := json.MarshalIndent(value, "", "  ")
	if err != nil {
		return fmt.Errorf("编码 %s 失败: %w", name, err)
	}
	if err := os.MkdirAll(s.Dir, 0o700); err != nil {
		return fmt.Errorf("创建数据目录失败: %w", err)
	}
	temporary, err := os.CreateTemp(s.Dir, ".tucao-*.json")
	if err != nil {
		return fmt.Errorf("创建临时文件失败: %w", err)
	}
	temporaryName := temporary.Name()
	defer os.Remove(temporaryName)
	if err := temporary.Chmod(0o600); err != nil {
		temporary.Close()
		return fmt.Errorf("设置文件权限失败: %w", err)
	}
	if _, err := temporary.Write(append(data, '\n')); err != nil {
		temporary.Close()
		return fmt.Errorf("写入 %s 失败: %w", name, err)
	}
	if err := temporary.Sync(); err != nil {
		temporary.Close()
		return fmt.Errorf("同步 %s 失败: %w", name, err)
	}
	if err := temporary.Close(); err != nil {
		return fmt.Errorf("关闭 %s 失败: %w", name, err)
	}
	if err := os.Rename(temporaryName, s.Path(name)); err != nil {
		return fmt.Errorf("替换 %s 失败: %w", name, err)
	}
	return nil
}

// Remove 删除数据文件, 文件不存在时不算失败.
func (s *Store) Remove(name string) error {
	err := os.Remove(s.Path(name))
	if errors.Is(err, os.ErrNotExist) {
		return nil
	}
	if err != nil {
		return fmt.Errorf("删除 %s 失败: %w", name, err)
	}
	return nil
}
