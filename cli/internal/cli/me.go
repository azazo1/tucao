package cli

import (
	"bufio"
	"fmt"
	"os"
	"strings"

	"github.com/spf13/cobra"
	"golang.org/x/term"

	"github.com/azazo1/tucao/cli/internal/api"
	"github.com/azazo1/tucao/cli/internal/output"
)

func (a *App) newMeCommand() *cobra.Command {
	var noCheck bool
	command := &cobra.Command{
		Use:   "me",
		Short: "查看当前登录状态",
		Long: `查看当前登录状态.

默认会向站点确认一次登录态, 未登录或已失效时会清掉本地记录;
加 --no-check 只看本地保存的内容.`,
		Args: cobra.NoArgs,
		RunE: func(command *cobra.Command, _ []string) error {
			authStore, err := a.authOrErr()
			if err != nil {
				return a.fail(command, err, "")
			}
			user := authStore.User()
			if !noCheck && authStore.CookieCount() > 0 {
				client, err := a.clientOrErr()
				if err != nil {
					return a.fail(command, err, "")
				}
				fresh, err := client.UserInfo(command.Context())
				if err != nil {
					return a.fail(command, err, "查询登录状态")
				}
				if fresh == nil {
					if err := authStore.Clear(); err != nil {
						a.Logger.Warn("清理本地登录态失败", "error", err)
					}
					user = nil
				} else {
					user = fresh
					if err := authStore.SetUser(fresh); err != nil {
						a.Logger.Warn("保存登录信息失败", "error", err)
					}
				}
			}
			payload := map[string]any{
				"logged_in":    user != nil,
				"user":         user,
				"cookie_count": authStore.CookieCount(),
				"user_file":    authStore.File,
			}
			return a.finish(command, payload, func(mode output.Mode) {
				if user == nil {
					a.Out.Line(mode, "未登录, 用 tucao me login 登录")
					return
				}
				a.Out.Line(mode, "%s (%d)  %s", user.DisplayName(), user.UserID, user.GroupName)
				a.Out.Line(mode, "本地登录信息: %s", authStore.File)
			})
		},
	}
	command.Flags().BoolVar(&noCheck, "no-check", false, "不向站点确认登录态")
	command.AddCommand(
		a.newLoginCommand(),
		a.newLogoutCommand(),
		a.newRegisterCommand(),
		a.newPasswordCommand(),
		a.newForgotCommand(),
	)
	return command
}

func (a *App) newLoginCommand() *cobra.Command {
	var (
		username   string
		password   string
		questionID string
		answer     string
	)
	command := &cobra.Command{
		Use:   "login",
		Short: "登录",
		Long: `用站点账号登录.

用户名与密码可以来自 --username / --password, 环境变量
TUCAO_USERNAME / TUCAO_PASSWORD, 或在交互终端里按提示输入.
密码不会写进日志, 登录成功后的 cookie 保存在 auth.json 里.`,
		Args: cobra.NoArgs,
		RunE: func(command *cobra.Command, _ []string) error {
			reader := bufio.NewReader(os.Stdin)
			name, err := requireInput(command, username, "TUCAO_USERNAME", "用户名: ", reader, false)
			if err != nil {
				return a.invalidInput(command, err.Error())
			}
			secret, err := requireInput(command, password, "TUCAO_PASSWORD", "密码: ", reader, true)
			if err != nil {
				return a.invalidInput(command, err.Error())
			}
			client, err := a.clientOrErr()
			if err != nil {
				return a.fail(command, err, "")
			}
			raw, err := client.Login(command.Context(), name, secret, questionID, answer)
			if err != nil {
				return a.fail(command, err, "登录")
			}
			if message := api.LoginFailure(raw); message != "" {
				return a.fail(command, api.NewError(api.CodeNotAuthenticated, "登录", message), "")
			}
			authStore, err := a.authOrErr()
			if err != nil {
				return a.fail(command, err, "")
			}
			user, err := client.UserInfo(command.Context())
			if err != nil {
				return a.fail(command, err, "确认登录状态")
			}
			if user == nil || user.UserID <= 0 {
				_ = authStore.Clear()
				return a.fail(command, api.NewError(api.CodeNotAuthenticated, "登录",
					"登录失败, 请检查用户名与密码"), "")
			}
			if err := authStore.SetUser(user); err != nil {
				return a.fail(command, api.WrapError(api.CodeInternal, "保存登录信息", err.Error(), err), "")
			}
			return a.finish(command, map[string]any{
				"logged_in": true,
				"user":      user,
				"user_file": authStore.File,
			}, func(mode output.Mode) {
				a.Out.Line(mode, "已登录: %s (%d)", user.DisplayName(), user.UserID)
			})
		},
	}
	command.Flags().StringVarP(&username, "username", "u", "", "用户名")
	command.Flags().StringVarP(&password, "password", "p", "", "密码")
	command.Flags().StringVar(&questionID, "question-id", "", "安全提问编号")
	command.Flags().StringVar(&answer, "answer", "", "安全提问答案")
	return command
}

func (a *App) newLogoutCommand() *cobra.Command {
	return &cobra.Command{
		Use:   "logout",
		Short: "退出登录",
		Long:  "退出站点登录并清除本地 cookie 与登录信息.",
		Args:  cobra.NoArgs,
		RunE: func(command *cobra.Command, _ []string) error {
			authStore, err := a.authOrErr()
			if err != nil {
				return a.fail(command, err, "")
			}
			if client, err := a.clientOrErr(); err == nil && authStore.CookieCount() > 0 {
				if err := client.Logout(command.Context()); err != nil {
					a.Logger.Warn("退出登录请求失败", "error", err)
				}
			}
			if err := authStore.Clear(); err != nil {
				return a.fail(command, api.WrapError(api.CodeInternal, "清除登录信息", err.Error(), err), "")
			}
			return a.finish(command, map[string]any{"logged_in": false}, func(mode output.Mode) {
				a.Out.Line(mode, "已退出登录")
			})
		},
	}
}

func (a *App) newRegisterCommand() *cobra.Command {
	var (
		username string
		nickname string
		email    string
		password string
		confirm  string
	)
	command := &cobra.Command{
		Use:   "register",
		Short: "注册账号",
		Long:  "在站点注册新账号, 与安卓端的注册页使用同一套表单字段.",
		Args:  cobra.NoArgs,
		RunE: func(command *cobra.Command, _ []string) error {
			reader := bufio.NewReader(os.Stdin)
			name, err := requireInput(command, username, "TUCAO_USERNAME", "用户名: ", reader, false)
			if err != nil {
				return a.invalidInput(command, err.Error())
			}
			mail, err := requireInput(command, email, "TUCAO_EMAIL", "邮箱: ", reader, false)
			if err != nil {
				return a.invalidInput(command, err.Error())
			}
			secret, err := requireInput(command, password, "TUCAO_PASSWORD", "密码: ", reader, true)
			if err != nil {
				return a.invalidInput(command, err.Error())
			}
			displayName := strings.TrimSpace(nickname)
			if displayName == "" {
				displayName = name
			}
			client, err := a.clientOrErr()
			if err != nil {
				return a.fail(command, err, "")
			}
			raw, err := client.Register(command.Context(), name, displayName, mail, secret, confirm)
			if err != nil {
				return a.fail(command, err, "注册")
			}
			if message := api.FormFailure(raw, "注册失败, 请检查填写的信息"); message != "" {
				return a.fail(command, api.NewError(api.CodeUpstream, "注册", message), "")
			}
			authStore, err := a.authOrErr()
			if err != nil {
				return a.fail(command, err, "")
			}
			user, err := client.UserInfo(command.Context())
			if err != nil || user == nil {
				return a.finish(command, map[string]any{
					"registered": true,
					"logged_in":  false,
				}, func(mode output.Mode) {
					a.Out.Line(mode, "注册成功, 但自动登录失败, 请用 tucao me login 登录")
				})
			}
			if err := authStore.SetUser(user); err != nil {
				a.Logger.Warn("保存登录信息失败", "error", err)
			}
			return a.finish(command, map[string]any{
				"registered": true,
				"logged_in":  true,
				"user":       user,
			}, func(mode output.Mode) {
				a.Out.Line(mode, "注册成功并已登录: %s", user.DisplayName())
			})
		},
	}
	command.Flags().StringVarP(&username, "username", "u", "", "用户名")
	command.Flags().StringVar(&nickname, "nickname", "", "昵称, 留空时与用户名相同")
	command.Flags().StringVar(&email, "email", "", "邮箱")
	command.Flags().StringVarP(&password, "password", "p", "", "密码")
	command.Flags().StringVar(&confirm, "confirm", "", "确认密码, 留空时与密码相同")
	return command
}

func (a *App) newPasswordCommand() *cobra.Command {
	var (
		oldPassword string
		newPassword string
		confirm     string
	)
	command := &cobra.Command{
		Use:   "password",
		Short: "修改密码",
		Long: `修改站点账号密码, 需要登录.

与安卓端一致: 修改成功后本地登录态会被清除, 需要重新登录.`,
		Args: cobra.NoArgs,
		RunE: func(command *cobra.Command, _ []string) error {
			if err := a.requireLoginWrite("修改密码"); err != nil {
				return a.fail(command, err, "")
			}
			reader := bufio.NewReader(os.Stdin)
			oldSecret, err := requireInput(command, oldPassword, "TUCAO_OLD_PASSWORD", "当前密码: ", reader, true)
			if err != nil {
				return a.invalidInput(command, err.Error())
			}
			newSecret, err := requireInput(command, newPassword, "TUCAO_NEW_PASSWORD", "新密码: ", reader, true)
			if err != nil {
				return a.invalidInput(command, err.Error())
			}
			client, err := a.clientOrErr()
			if err != nil {
				return a.fail(command, err, "")
			}
			raw, err := client.ChangePassword(command.Context(), oldSecret, newSecret, confirm)
			if err != nil {
				return a.fail(command, err, "修改密码")
			}
			if message := api.FormFailure(raw, "修改密码失败, 请检查填写的信息"); message != "" {
				return a.fail(command, api.NewError(api.CodeUpstream, "修改密码", message), "")
			}
			authStore, err := a.authOrErr()
			if err == nil {
				if clearErr := authStore.Clear(); clearErr != nil {
					a.Logger.Warn("清除本地登录态失败", "error", clearErr)
				}
			}
			return a.finish(command, map[string]any{"changed": true, "logged_in": false}, func(mode output.Mode) {
				a.Out.Line(mode, "密码已修改, 本地登录态已清除, 请重新登录")
			})
		},
	}
	command.Flags().StringVar(&oldPassword, "old", "", "当前密码")
	command.Flags().StringVar(&newPassword, "new", "", "新密码")
	command.Flags().StringVar(&confirm, "confirm", "", "确认新密码, 留空时与新密码相同")
	return command
}

func (a *App) newForgotCommand() *cobra.Command {
	command := &cobra.Command{
		Use:   "forgot",
		Short: "通过邮箱找回密码",
		Long: `分两步找回密码.

先执行 tucao me forgot captcha 把图形验证码存成图片给人或 agent 看,
再用同一个会话执行 tucao me forgot submit --email ... --code ...;
两步必须紧挨着执行, 站点按 cookie 里的会话校验验证码.`,
		Args: cobra.NoArgs,
		RunE: func(command *cobra.Command, _ []string) error {
			return a.invalidInput(command, "请使用 tucao me forgot captcha 或 tucao me forgot submit")
		},
	}
	command.AddCommand(a.newForgotCaptchaCommand(), a.newForgotSubmitCommand())
	return command
}

func (a *App) newForgotCaptchaCommand() *cobra.Command {
	var outputPath string
	command := &cobra.Command{
		Use:   "captcha",
		Short: "下载图形验证码",
		Args:  cobra.NoArgs,
		RunE: func(command *cobra.Command, _ []string) error {
			client, err := a.clientOrErr()
			if err != nil {
				return a.fail(command, err, "")
			}
			payload, err := client.CheckCode(command.Context())
			if err != nil {
				return a.fail(command, err, "获取验证码")
			}
			path := strings.TrimSpace(outputPath)
			if path == "" {
				path = "tucao-captcha.png"
			}
			if err := os.WriteFile(path, payload, 0o644); err != nil {
				return a.fail(command, api.WrapError(api.CodeInternal, "保存验证码", err.Error(), err), "")
			}
			return a.finish(command, map[string]any{
				"path":  path,
				"bytes": len(payload),
			}, func(mode output.Mode) {
				a.Out.Line(mode, "验证码已保存: %s", path)
				a.Out.Line(mode, "看完后执行: tucao me forgot submit --email <邮箱> --code <验证码>")
			})
		},
	}
	command.Flags().StringVarP(&outputPath, "output", "o", "", "验证码图片路径, 默认 tucao-captcha.png")
	return command
}

func (a *App) newForgotSubmitCommand() *cobra.Command {
	var (
		email string
		code  string
	)
	command := &cobra.Command{
		Use:   "submit",
		Short: "提交邮箱与验证码",
		Args:  cobra.NoArgs,
		RunE: func(command *cobra.Command, _ []string) error {
			if strings.TrimSpace(email) == "" || strings.TrimSpace(code) == "" {
				return a.invalidInput(command, "需要 --email 与 --code")
			}
			if err := a.requireWrite("找回密码"); err != nil {
				return a.fail(command, err, "")
			}
			client, err := a.clientOrErr()
			if err != nil {
				return a.fail(command, err, "")
			}
			result, err := client.ForgotPassword(command.Context(), strings.TrimSpace(email), strings.TrimSpace(code))
			if err != nil {
				return a.fail(command, err, "找回密码")
			}
			if !result.IsSuccess() {
				return a.fail(command, api.NewError(api.CodeUpstream, "找回密码", result.Message), "")
			}
			return a.finish(command, map[string]any{
				"email":   email,
				"status":  result.Status,
				"message": result.Message,
			}, func(mode output.Mode) {
				a.Out.Line(mode, "%s", result.Message)
			})
		},
	}
	command.Flags().StringVar(&email, "email", "", "注册邮箱")
	command.Flags().StringVar(&code, "code", "", "图片里的验证码")
	return command
}

// requireInput 依次从参数, 环境变量与交互终端取输入.
//
// secret 为真时在交互终端里关闭回显; 非交互场景不会等待输入,
// 直接报错提示改用参数或环境变量.
func requireInput(command *cobra.Command, value, envName, prompt string, reader *bufio.Reader, secret bool) (string, error) {
	if trimmed := strings.TrimSpace(value); trimmed != "" {
		return trimmed, nil
	}
	if fromEnv := os.Getenv(envName); strings.TrimSpace(fromEnv) != "" {
		return strings.TrimSpace(fromEnv), nil
	}
	if !output.IsTerminal(os.Stderr) {
		return "", fmt.Errorf("缺少输入, 可用参数或环境变量 %s 提供", envName)
	}
	fmt.Fprint(os.Stderr, prompt)
	if secret {
		if data, err := term.ReadPassword(int(os.Stdin.Fd())); err == nil {
			fmt.Fprintln(os.Stderr)
			return strings.TrimSpace(string(data)), nil
		}
	}
	line, err := reader.ReadString('\n')
	if err != nil && strings.TrimSpace(line) == "" {
		return "", fmt.Errorf("读取输入失败")
	}
	return strings.TrimSpace(line), nil
}
