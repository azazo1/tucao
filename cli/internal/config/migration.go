package config

import "fmt"

// migrate 把旧版本的配置补齐到当前版本.
//
// 版本号为 0 表示配置里没有 version 字段, 属于 early 版本或手工创建的配置,
// 统一按缺失字段补齐处理; 高于当前版本时直接报错, 避免新版字段被旧程序抹掉.
func migrate(config Config, sourceVersion int) (Config, bool, error) {
	switch {
	case sourceVersion == 0:
		config = mergeDefaults(config)
		config.Version = CurrentVersion
		return config, true, nil
	case sourceVersion == CurrentVersion:
		return config, false, nil
	case sourceVersion > CurrentVersion:
		return Config{}, false, fmt.Errorf("config.toml 版本 %d 高于当前支持版本 %d", sourceVersion, CurrentVersion)
	default:
		return Config{}, false, fmt.Errorf("不支持的 config.toml 版本: %d", sourceVersion)
	}
}

// mergeDefaults 只补齐缺省字段, 已经写过的值保持不动.
func mergeDefaults(config Config) Config {
	defaults := Default()
	if config.Output.Format == "" {
		config.Output.Format = defaults.Output.Format
	}
	if config.Network.TimeoutSeconds == 0 {
		config.Network.TimeoutSeconds = defaults.Network.TimeoutSeconds
	}
	if config.Site.Host == "" {
		config.Site.Host = defaults.Site.Host
	}
	if config.Download.Threads == 0 {
		config.Download.Threads = defaults.Download.Threads
	}
	if config.Danmaku.Font == "" {
		config.Danmaku.Font = defaults.Danmaku.Font
	}
	if config.Danmaku.FontSize == 0 {
		config.Danmaku.FontSize = defaults.Danmaku.FontSize
	}
	if config.History.Limit == 0 {
		config.History.Limit = defaults.History.Limit
	}
	return config
}
