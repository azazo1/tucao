package cli

import (
	"github.com/spf13/cobra"

	"github.com/azazo1/tucao/cli/internal/api"
	"github.com/azazo1/tucao/cli/internal/model"
	"github.com/azazo1/tucao/cli/internal/output"
)

func (a *App) newSearchCommand() *cobra.Command {
	var (
		channel   string
		order     string
		page      int
		pageSize  int
		noHistory bool
	)
	command := &cobra.Command{
		Use:   "search 关键词",
		Short: "搜索视频",
		Long: `按关键词搜索视频.

搜索过的关键词会记进本地搜索历史, 用 tucao history search 查看;
脚本或 agent 不希望写入历史时加 --no-history.`,
		Args: cobra.ExactArgs(1),
		RunE: func(command *cobra.Command, args []string) error {
			keyword := args[0]
			typeID, err := resolveChannelRef(channel)
			if err != nil {
				return a.fail(command, err, "")
			}
			if err := validateOrder(order); err != nil {
				return a.fail(command, err, "")
			}
			client, err := a.clientOrErr()
			if err != nil {
				return a.fail(command, err, "")
			}
			list, err := client.VideoSearch(command.Context(), keyword, typeID, page, pageSize, order)
			if err != nil {
				return a.fail(command, err, "搜索视频")
			}
			if !noHistory {
				a.recordSearchHistory(keyword)
			}
			return a.finish(command, list, func(mode output.Mode) {
				a.renderVideoList(mode, "搜索 "+keyword, list)
			})
		},
	}
	command.Flags().StringVarP(&channel, "channel", "c", "", "分区编号或名字, 留空搜索全站")
	command.Flags().StringVarP(&order, "order", "o", api.OrderDate, "排序: date, mukio, views")
	command.Flags().IntVar(&page, "page", 1, "页码, 从 1 开始")
	command.Flags().IntVar(&pageSize, "page-size", 20, "每页条数")
	command.Flags().BoolVar(&noHistory, "no-history", false, "不写入本地搜索历史")
	return command
}

// recordSearchHistory 记录搜索关键词, 失败只记日志, 不影响搜索结果.
func (a *App) recordSearchHistory(keyword string) {
	dataStore, err := a.dataOrErr()
	if err != nil {
		return
	}
	history, err := dataStore.LoadSearchHistory()
	if err != nil {
		a.Logger.Warn("读取搜索历史失败", "error", err)
		return
	}
	history.Add(keyword, a.Config.Search.HistoryLimit)
	if err := dataStore.SaveSearchHistory(history); err != nil {
		a.Logger.Warn("保存搜索历史失败", "error", err)
	}
}

// renderVideoDetail 输出视频详情.
func (a *App) renderVideoDetail(mode output.Mode, detail *model.VideoDetail) {
	if mode != output.ModeRich {
		return
	}
	video := detail.Video
	a.Out.Line(mode, "%s  [%s]", video.Title, video.HID)
	a.Out.Line(mode, "分区: %s (%d)   UP主: %s (%d)", video.TypeName, video.TypeID, video.UserName, video.UserID)
	a.Out.Line(mode, "发布时间: %s   站内地址: %s", video.CreateAt, video.SiteURL)
	a.Out.Line(mode, "播放: %s   弹幕: %s   分P: %d", humanCount(video.PlayCount), humanCount(video.DanmakuCount), video.PartCount)
	if detail.Stats != nil {
		a.Out.Line(mode, "统计: 播放 %s   在线 %s   评论 %s   追番 %s",
			countText(detail.Stats.PlayCount),
			countText(detail.Stats.OnlineCount),
			countText(detail.Stats.CommentCount),
			countText(detail.Stats.FavoriteCount),
		)
	}
	if len(video.Parts) > 0 {
		rows := make([][]string, 0, len(video.Parts))
		for _, part := range video.Parts {
			source := "第三方源"
			if part.File != "" {
				source = "直链"
			}
			rows = append(rows, []string{itoaPlain(part.Number), part.Title, source, part.File})
		}
		a.Out.RenderTable(mode, "分P", []string{"序号", "标题", "来源", "直链"}, rows)
	}
	if len(detail.Subject) > 0 {
		rows := make([][]string, 0, len(detail.Subject))
		for _, field := range detail.Subject {
			rows = append(rows, []string{field.Label, field.Value})
		}
		a.Out.RenderTable(mode, "番组信息", []string{"字段", "值"}, rows)
	}
	description := detail.FullDescription
	if description == "" {
		description = video.Description
	}
	if description != "" {
		a.Out.Line(mode, "")
		a.Out.Line(mode, "简介:")
		a.Out.Line(mode, "%s", description)
	}
}
