package auth

import (
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"github.com/azazo1/tucao/cli/internal/model"
	"github.com/azazo1/tucao/cli/internal/paths"
)

// CurrentVersion 是 auth.json 的结构版本.
const CurrentVersion = 1

// Session 是 auth.json 的内容, 保存整份 cookie 与登录用户.
type Session struct {
	Version int         `json:"version"`
	SavedAt int64       `json:"saved_at"`
	Cookies []Cookie    `json:"cookies"`
	User    *model.User `json:"user,omitempty"`
}

// Store 负责 auth.json 的读写与 cookie 容器.
//
// 站点用 cookie 维持登录态, 因此 cookie 变更后立即回写文件,
// 保证下一个命令进程仍然带着同一份登录态.
type Store struct {
	Dir    string
	File   string
	Logger *slog.Logger

	jar  *Jar
	mu   sync.Mutex
	user *model.User
}

// NewStore 定位 auth.json 并构造带回写的 cookie 容器.
func NewStore() *Store {
	dir := paths.ConfigDir()
	store := &Store{
		Dir:    dir,
		File:   filepath.Join(dir, "auth.json"),
		Logger: slog.Default(),
	}
	store.jar = newJar(func() { store.persistAfterChange() })
	return store
}

// Jar 返回 cookie 容器, 可直接交给 http 客户端.
func (s *Store) Jar() *Jar { return s.jar }

// Load 读取 auth.json, 文件不存在时视为未登录.
func (s *Store) Load() error {
	data, err := os.ReadFile(s.File)
	if errors.Is(err, os.ErrNotExist) {
		return nil
	}
	if err != nil {
		return fmt.Errorf("读取登录信息失败: %w", err)
	}
	var session Session
	if err := json.Unmarshal(data, &session); err != nil {
		return fmt.Errorf("解析 auth.json 失败: %w", err)
	}
	if session.Version > CurrentVersion {
		return fmt.Errorf("auth.json 版本 %d 高于当前支持版本 %d", session.Version, CurrentVersion)
	}
	s.jar.Load(session.Cookies)
	s.mu.Lock()
	s.user = session.User
	s.mu.Unlock()
	s.logger().Debug("已读取登录态", "cookies", len(session.Cookies), "logged_in", session.User != nil)
	return nil
}

// logger 返回日志出口, 未注入时使用默认出口.
func (s *Store) logger() *slog.Logger {
	if s.Logger == nil {
		return slog.Default()
	}
	return s.Logger
}

// User 返回当前登录用户, 未登录时为 nil.
func (s *Store) User() *model.User {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.user
}

// LoggedIn 判断本地是否保存了登录用户.
func (s *Store) LoggedIn() bool {
	return s.User() != nil
}

// CookieCount 返回保存的 cookie 条数.
func (s *Store) CookieCount() int { return s.jar.Count() }

// SetUser 记录登录用户并回写文件.
func (s *Store) SetUser(user *model.User) error {
	s.mu.Lock()
	s.user = user
	s.mu.Unlock()
	return s.Save()
}

// Save 把当前 cookie 与用户写入 auth.json.
func (s *Store) Save() error {
	s.mu.Lock()
	user := s.user
	s.mu.Unlock()
	cookies := s.jar.Entries()
	if len(cookies) == 0 && user == nil {
		return s.remove()
	}
	session := Session{
		Version: CurrentVersion,
		SavedAt: time.Now().Unix(),
		Cookies: cookies,
		User:    user,
	}
	if session.Cookies == nil {
		session.Cookies = []Cookie{}
	}
	data, err := json.MarshalIndent(session, "", "  ")
	if err != nil {
		return fmt.Errorf("编码登录信息失败: %w", err)
	}
	return s.write(append(data, '\n'))
}

// Clear 删除本地登录态与 cookie.
func (s *Store) Clear() error {
	s.jar.Clear()
	s.mu.Lock()
	s.user = nil
	s.mu.Unlock()
	return s.remove()
}

// ImportCookieHeader 从 cookie 头字符串导入登录态, 常用于已登录的浏览器会话.
func (s *Store) ImportCookieHeader(host, raw string) int {
	count := 0
	for _, part := range strings.Split(raw, ";") {
		pair := strings.SplitN(strings.TrimSpace(part), "=", 2)
		if len(pair) != 2 || pair[0] == "" {
			continue
		}
		s.jar.Set(host, pair[0], pair[1])
		count++
	}
	return count
}

// persistAfterChange 在 cookie 变更后回写文件, 失败只记日志.
func (s *Store) persistAfterChange() {
	if err := s.Save(); err != nil {
		s.logger().Warn("保存登录信息失败", "error", err)
	}
}

func (s *Store) remove() error {
	err := os.Remove(s.File)
	if errors.Is(err, os.ErrNotExist) {
		return nil
	}
	if err != nil {
		return fmt.Errorf("删除登录信息失败: %w", err)
	}
	return nil
}

func (s *Store) write(data []byte) error {
	if err := os.MkdirAll(s.Dir, 0o700); err != nil {
		return fmt.Errorf("创建配置目录失败: %w", err)
	}
	temporary, err := os.CreateTemp(s.Dir, ".auth-*.json")
	if err != nil {
		return fmt.Errorf("创建临时登录信息失败: %w", err)
	}
	name := temporary.Name()
	defer os.Remove(name)
	if err := temporary.Chmod(0o600); err != nil {
		temporary.Close()
		return fmt.Errorf("设置登录信息权限失败: %w", err)
	}
	if _, err := temporary.Write(data); err != nil {
		temporary.Close()
		return fmt.Errorf("写入登录信息失败: %w", err)
	}
	if err := temporary.Close(); err != nil {
		return fmt.Errorf("关闭临时登录信息失败: %w", err)
	}
	if err := os.Rename(name, s.File); err != nil {
		return fmt.Errorf("替换登录信息失败: %w", err)
	}
	return nil
}
