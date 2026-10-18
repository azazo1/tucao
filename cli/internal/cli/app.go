package cli

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"os"
	"strings"
	"sync"
	"time"

	"github.com/spf13/cobra"

	"github.com/azazo1/tucao/cli/internal/api"
	"github.com/azazo1/tucao/cli/internal/auth"
	"github.com/azazo1/tucao/cli/internal/config"
	"github.com/azazo1/tucao/cli/internal/output"
	"github.com/azazo1/tucao/cli/internal/store"
)

// Version 是命令版本, 由构建脚本按 git tag 注入.
var Version = "devel"

// ExitError 携带进程退出码, 由 main 直接使用.
type ExitError struct {
	Code int
}

func (e *ExitError) Error() string {
	return fmt.Sprintf("exit status %d", e.Code)
}

// App 保存命令层共享的依赖.
type App struct {
	Out         *output.Writer
	Config      config.Config
	ConfigStore *config.Store
	ConfigErr   error
	ConfigWarn  error
	Logger      *slog.Logger

	root *cobra.Command

	verbose    bool
	asJSON     bool
	asYAML     bool
	asExplicit bool

	clientOnce sync.Once
	client     *api.Client
	clientErr  error

	authOnce  sync.Once
	authStore *auth.Store
	authErr   error

	storeOnce sync.Once
	dataStore *store.Store
}

// NewApp 构造命令应用.
//
// 配置文件缺失时会写入默认配置; 目录不可写 (例如只读沙箱) 时退回默认值继续,
// 只有配置文件存在但无法解析才算需要用户处理的错误.
func NewApp() *App {
	app := &App{
		Out:         output.NewWriter(),
		ConfigStore: config.NewStore(),
		Logger:      slog.New(slog.NewTextHandler(os.Stderr, &slog.HandlerOptions{Level: slog.LevelWarn})),
	}
	configValue, err := app.ConfigStore.Ensure()
	switch {
	case err == nil:
		app.Config = configValue
	case errors.Is(err, config.ErrParse):
		app.Config = config.Default()
		app.ConfigErr = err
	default:
		app.Config = config.Default()
		app.ConfigWarn = err
	}
	if app.Config.Output.Format != "" {
		app.Out.DefaultMode = app.Config.Output.Format
	}
	app.Out.NoTruncate = !app.Config.Output.Truncate
	return app
}

// Execute 执行命令并返回带上退出码的错误.
//
// cobra 自己抛出的用法错误 (未知命令, 未知参数) 也归到 invalid_input,
// 保证脚本按退出码 2 就能识别出调用方式不对.
func (a *App) Execute(ctx context.Context) error {
	a.root = a.newRoot()
	if err := a.root.ExecuteContext(ctx); err != nil {
		var exitErr *ExitError
		if errors.As(err, &exitErr) {
			return exitErr
		}
		if looksLikeUsageError(err) {
			return a.failUsage(a.root, err)
		}
		return a.fail(a.root, err, "")
	}
	return nil
}

// looksLikeUsageError 判断错误是否属于命令行用法问题.
func looksLikeUsageError(err error) bool {
	message := err.Error()
	for _, prefix := range []string{"unknown command", "unknown flag", "unknown shorthand flag", "invalid argument", "requires at"} {
		if strings.HasPrefix(message, prefix) {
			return true
		}
	}
	return false
}

// setupLogging 按 --verbose 调整日志级别.
func (a *App) setupLogging(verbose bool) {
	level := slog.LevelWarn
	if verbose {
		level = slog.LevelDebug
	}
	a.Logger = slog.New(slog.NewTextHandler(os.Stderr, &slog.HandlerOptions{Level: level}))
	if a.ConfigWarn != nil {
		a.Logger.Warn("配置文件不可写, 本次使用默认配置", "error", a.ConfigWarn)
	}
	if a.client != nil {
		a.client.Logger = a.Logger
	}
	if a.authStore != nil {
		a.authStore.Logger = a.Logger
	}
}

// mode 解析当前命令的输出格式.
func (a *App) mode(command *cobra.Command) output.Mode {
	asJSON, asYAML := a.asJSON, a.asYAML
	if command != nil {
		if value, err := command.Flags().GetBool("json"); err == nil && value {
			asJSON = true
		}
		if value, err := command.Flags().GetBool("yaml"); err == nil && value {
			asYAML = true
		}
	}
	mode, err := a.Out.Resolve(asJSON, asYAML)
	if err != nil {
		return output.ModeRich
	}
	return mode
}

// clientOrErr 返回站点客户端, 首次调用时按配置构造.
func (a *App) clientOrErr() (*api.Client, error) {
	a.clientOnce.Do(func() {
		if a.ConfigErr != nil {
			a.clientErr = a.ConfigErr
			return
		}
		authStore, err := a.authOrErr()
		if err != nil {
			a.clientErr = err
			return
		}
		client := api.NewClient(a.Config.BaseURL(), authStore.Jar(), a.Logger)
		client.SetTimeout(time.Duration(a.Config.Network.TimeoutSeconds) * time.Second)
		client.Retries = a.Config.Network.Retries
		a.client = client
	})
	return a.client, a.clientErr
}

// authOrErr 返回登录态存取对象, 首次调用时读入 auth.json.
func (a *App) authOrErr() (*auth.Store, error) {
	a.authOnce.Do(func() {
		authStore := auth.NewStore()
		authStore.Logger = a.Logger
		if err := authStore.Load(); err != nil {
			a.authErr = api.WrapError(api.CodeInternal, "读取登录信息", err.Error(), err)
			return
		}
		if raw := os.Getenv("TUCAO_COOKIE"); raw != "" && authStore.CookieCount() == 0 {
			count := authStore.ImportCookieHeader(a.Config.Site.Host, raw)
			a.Logger.Debug("已从 TUCAO_COOKIE 导入 cookie", "count", count)
		}
		a.authStore = authStore
	})
	return a.authStore, a.authErr
}

// dataOrErr 返回本地数据存取对象.
func (a *App) dataOrErr() (*store.Store, error) {
	a.storeOnce.Do(func() {
		a.dataStore = store.NewStore()
	})
	return a.dataStore, nil
}

// finish 输出结构化结果, rich 模式下先渲染人类可读的内容.
func (a *App) finish(command *cobra.Command, data any, rich func(mode output.Mode)) error {
	mode := a.mode(command)
	if mode == output.ModeRich && rich != nil {
		rich(mode)
	}
	if err := a.Out.EmitSuccess(data, mode); err != nil {
		return a.fail(command, api.WrapError(api.CodeInternal, "", "写出结果失败", err), "")
	}
	return nil
}

// fail 按当前输出格式报告错误, 并返回带退出码的错误.
func (a *App) fail(command *cobra.Command, err error, action string) error {
	if err == nil {
		return nil
	}
	mode := a.mode(command)
	message := err.Error()
	var apiErr *api.Error
	if action != "" && (!errors.As(err, &apiErr) || apiErr.Action == "") {
		message = action + ": " + message
	}
	if emitErr := a.Out.EmitError(string(api.CodeOf(err)), message, nil, mode); emitErr != nil {
		fmt.Fprintln(a.Out.Stderr, message)
	}
	return &ExitError{Code: api.ExitCode(err)}
}

// invalidInput 报告参数错误.
func (a *App) invalidInput(command *cobra.Command, message string) error {
	return a.fail(command, api.NewError(api.CodeInvalidInput, "", message), "")
}

// requireLogin 在需要登录态的命令里做前置检查.
func (a *App) requireLogin(action string) error {
	authStore, err := a.authOrErr()
	if err != nil {
		return err
	}
	if !authStore.LoggedIn() && authStore.CookieCount() == 0 {
		return api.NotLoggedIn(action)
	}
	return nil
}
