package cli

import (
	"github.com/spf13/cobra"

	"github.com/azazo1/tucao/cli/internal/api"
	"github.com/azazo1/tucao/cli/internal/output"
)

// validateOrder 校验列表排序参数.
func validateOrder(order string) error {
	switch order {
	case api.OrderDate, api.OrderDanmaku, api.OrderViews:
		return nil
	default:
		return api.NewError(api.CodeInvalidInput, "", "排序只支持 date, mukio 与 views")
	}
}

// resolveChannelRef 把分区编号或名字解析成编号.
func resolveChannelRef(raw string) (int, error) {
	if raw == "" {
		return 0, nil
	}
	channel, ok := findChannel(raw)
	if !ok {
		return 0, api.NewError(api.CodeInvalidInput, "", "未知分区: "+raw)
	}
	return channel.ID, nil
}

func (a *App) newListCommand() *cobra.Command {
	var (
		channel  string
		order    string
		page     int
		pageSize int
	)
	command := &cobra.Command{
		Use:   "list",
		Short: "按分区列出视频",
		Long: `按分区列出视频.

分区可以用编号或名字, 例如 tucao list --channel 新番 或 tucao list --channel 24.`,
		Args: cobra.NoArgs,
		RunE: func(command *cobra.Command, _ []string) error {
			typeID, err := resolveChannelRef(channel)
			if err != nil || typeID == 0 {
				if err == nil {
					err = api.NewError(api.CodeInvalidInput, "", "请用 --channel 指定分区")
				}
				return a.fail(command, err, "")
			}
			if err := validateOrder(order); err != nil {
				return a.fail(command, err, "")
			}
			client, err := a.clientOrErr()
			if err != nil {
				return a.fail(command, err, "")
			}
			list, err := client.VideoList(command.Context(), typeID, page, pageSize, order)
			if err != nil {
				return a.fail(command, err, "获取分区列表")
			}
			title := channel
			if name, ok := findChannel(channel); ok {
				title = name.Name
			}
			return a.finish(command, list, func(mode output.Mode) {
				a.renderVideoList(mode, "分区 "+title, list)
			})
		},
	}
	command.Flags().StringVarP(&channel, "channel", "c", "24", "分区编号或名字, 默认 24 新番")
	command.Flags().StringVarP(&order, "order", "o", api.OrderDate, "排序: date, mukio, views")
	command.Flags().IntVar(&page, "page", 1, "页码, 从 1 开始")
	command.Flags().IntVar(&pageSize, "page-size", 20, "每页条数")
	return command
}
