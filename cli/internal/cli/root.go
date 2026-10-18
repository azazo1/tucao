package cli

import (
	"github.com/spf13/cobra"

	"github.com/azazo1/tucao/cli/internal/api"
)

// newRoot 构造根命令.
func (a *App) newRoot() *cobra.Command {
	var noTruncate bool
	root := &cobra.Command{
		Use:   "tucao",
		Short: "浏览, 搜索与下载吐槽弹幕网内容的命令行工具",
		Long: `吐槽弹幕网命令行工具.

按分区浏览与搜索站点内容, 查看排行榜, 番组索引, 档案, 用户空间, 私信与评论,
拉取并导出弹幕, 下载单文件分P, 以及登录与本地收藏管理.

配置保存在 ~/.config/tucao/config.toml, 登录态保存在 ~/.config/tucao/auth.json,
收藏与播放历史保存在 ~/.local/share/tucao/ 下.`,
		Version:       Version,
		SilenceUsage:  true,
		SilenceErrors: true,
		PersistentPreRunE: func(command *cobra.Command, _ []string) error {
			a.setupLogging(a.verbose)
			if noTruncate {
				a.Out.NoTruncate = true
			}
			if a.ConfigErr != nil && !isConfigRecoveryCommand(command.CommandPath()) {
				return a.fail(command, api.NewError(api.CodeInvalidInput, "",
					"加载 config.toml 失败: "+a.ConfigErr.Error()), "")
			}
			return nil
		},
	}
	root.SetVersionTemplate("{{.Version}}\n")
	root.PersistentFlags().BoolVarP(&a.verbose, "verbose", "v", false, "输出调试日志")
	root.PersistentFlags().BoolVar(&a.asJSON, "json", false, "以 JSON 输出结果")
	root.PersistentFlags().BoolVar(&a.asYAML, "yaml", false, "以 YAML 输出结果")
	root.PersistentFlags().BoolVar(&noTruncate, "no-truncate", false, "表格不按终端宽度截断")

	root.AddCommand(
		a.newHomeCommand(),
		a.newChannelCommand(),
		a.newWeekCommand(),
		a.newListCommand(),
		a.newRankCommand(),
		a.newSearchCommand(),
		a.newVideoCommand(),
		a.newBgmCommand(),
		a.newArticleCommand(),
		a.newSpaceCommand(),
		a.newMessageCommand(),
		a.newMeCommand(),
		a.newFavCommand(),
		a.newHistoryCommand(),
		a.newAdCommand(),
		a.newUpdateCommand(),
		a.newConfigCommand(),
	)
	configureUsageErrors(root, a)
	return root
}

// isConfigRecoveryCommand 判断命令是否需要在配置损坏时仍然可用.
func isConfigRecoveryCommand(path string) bool {
	switch path {
	case "tucao config init", "tucao config status", "tucao config upgrade", "tucao config set":
		return true
	default:
		return false
	}
}
