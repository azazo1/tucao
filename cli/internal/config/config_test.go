package config

import (
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
)

func newTestStore(t *testing.T) *Store {
	t.Helper()
	dir := t.TempDir()
	return &Store{Dir: dir, File: filepath.Join(dir, "config.toml")}
}

func TestStoreEnsureCreatesDefaultFile(t *testing.T) {
	store := newTestStore(t)
	config, err := store.Ensure()
	if err != nil {
		t.Fatalf("Ensure 失败: %v", err)
	}
	if config.Version != CurrentVersion || config.Site.Host != "www.tucao.my" {
		t.Fatalf("默认配置不正确: %+v", config)
	}
	if !store.Exists() {
		t.Fatal("应写入默认配置文件")
	}
	data, err := os.ReadFile(store.File)
	if err != nil {
		t.Fatalf("读取配置文件失败: %v", err)
	}
	if !strings.Contains(string(data), "version = 1") {
		t.Fatalf("默认文件缺少版本号: %s", data)
	}
	info, err := os.Stat(store.File)
	if err != nil {
		t.Fatalf("读取文件信息失败: %v", err)
	}
	// Windows 不支持 unix 权限位, 读取到的永远是 0666 或 0444.
	if runtime.GOOS != "windows" && info.Mode().Perm() != 0o600 {
		t.Fatalf("配置文件权限应为 0600, 实际 %v", info.Mode().Perm())
	}
}

func TestStoreMigratesMissingVersion(t *testing.T) {
	store := newTestStore(t)
	content := "[output]\nformat = \"json\"\n\n[site]\nhost = \"www.tucao.my\"\n"
	if err := os.WriteFile(store.File, []byte(content), 0o600); err != nil {
		t.Fatalf("写入配置失败: %v", err)
	}
	config, err := store.Ensure()
	if err != nil {
		t.Fatalf("Ensure 失败: %v", err)
	}
	if config.Version != CurrentVersion {
		t.Fatalf("缺失版本号时应补到当前版本, 实际 %d", config.Version)
	}
	if config.Output.Format != "json" {
		t.Fatalf("已有字段不应被默认值覆盖: %q", config.Output.Format)
	}
	if config.Download.Threads != 4 {
		t.Fatalf("缺失字段应补齐默认值: %d", config.Download.Threads)
	}
	data, err := os.ReadFile(store.File)
	if err != nil {
		t.Fatalf("读取配置失败: %v", err)
	}
	if !strings.Contains(string(data), "version = 1") {
		t.Fatalf("迁移后应回写版本号: %s", data)
	}
}

func TestStoreRejectsBrokenConfig(t *testing.T) {
	store := newTestStore(t)
	if err := os.WriteFile(store.File, []byte("version = ???"), 0o600); err != nil {
		t.Fatalf("写入配置失败: %v", err)
	}
	if _, err := store.Ensure(); err == nil {
		t.Fatal("非法配置应当报错")
	} else if !strings.Contains(err.Error(), "解析 config.toml 失败") {
		t.Fatalf("解析错误信息不明确: %v", err)
	}
}

func TestStoreRejectsFutureVersion(t *testing.T) {
	store := newTestStore(t)
	if err := os.WriteFile(store.File, []byte("version = 99\n"), 0o600); err != nil {
		t.Fatalf("写入配置失败: %v", err)
	}
	if _, err := store.Ensure(); err == nil {
		t.Fatal("高于当前版本的配置应当报错")
	}
}

func TestValidateRejectsBadValues(t *testing.T) {
	cases := []struct {
		name   string
		mutate func(*Config)
	}{
		{name: "输出格式", mutate: func(c *Config) { c.Output.Format = "xml" }},
		{name: "超时为零", mutate: func(c *Config) { c.Network.TimeoutSeconds = -1 }},
		{name: "重试过多", mutate: func(c *Config) { c.Network.Retries = 9 }},
		{name: "域名非法", mutate: func(c *Config) { c.Site.Host = "不是域名" }},
		{name: "并发过大", mutate: func(c *Config) { c.Download.Threads = 99 }},
		{name: "字号过小", mutate: func(c *Config) { c.Danmaku.FontSize = 2 }},
		{name: "透明度越界", mutate: func(c *Config) { c.Danmaku.Opacity = 2 }},
		{name: "历史上限", mutate: func(c *Config) { c.History.Limit = -1 }},
		{name: "搜索历史上限", mutate: func(c *Config) { c.Search.HistoryLimit = -1 }},
	}
	for _, testCase := range cases {
		t.Run(testCase.name, func(t *testing.T) {
			config := Default()
			testCase.mutate(&config)
			if _, _, err := validate(config); err == nil {
				t.Fatal("非法值应当被拒绝")
			}
		})
	}
}

func TestValidateNormalizesHost(t *testing.T) {
	config := Default()
	config.Site.Host = "HTTPS://WWW.TUCAO.MY/"
	normalized, changed, err := validate(config)
	if err != nil {
		t.Fatalf("合法域名不应报错: %v", err)
	}
	if !changed || normalized.Site.Host != "www.tucao.my" {
		t.Fatalf("域名应被归一化: %+v", normalized.Site)
	}
	if normalized.BaseURL() != "https://www.tucao.my/" {
		t.Fatalf("站点地址不正确: %s", normalized.BaseURL())
	}
}

func TestStoreSaveAndLoad(t *testing.T) {
	store := newTestStore(t)
	if _, err := store.Ensure(); err != nil {
		t.Fatalf("Ensure 失败: %v", err)
	}
	config, err := store.Load()
	if err != nil {
		t.Fatalf("Load 失败: %v", err)
	}
	config.Site.Host = "tucao.example"
	config.Download.Threads = 8
	if err := store.Save(config); err != nil {
		t.Fatalf("Save 失败: %v", err)
	}
	reloaded, err := store.Load()
	if err != nil {
		t.Fatalf("重新读取失败: %v", err)
	}
	if reloaded.Site.Host != "tucao.example" || reloaded.Download.Threads != 8 {
		t.Fatalf("配置没有正确写回: %+v", reloaded)
	}
	if err := store.Save(Config{Version: CurrentVersion, Site: SiteConfig{Host: "bad"}}); err == nil {
		t.Fatal("保存非法配置应当报错")
	}
}
