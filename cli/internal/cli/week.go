package cli

import (
	"github.com/spf13/cobra"

	"github.com/azazo1/tucao/cli/internal/api"
	"github.com/azazo1/tucao/cli/internal/model"
	"github.com/azazo1/tucao/cli/internal/output"
)

// weekHeaders 是时间表与番组索引表格的列.
var weekHeaders = []string{"编号", "标题", "集数状态", "题材", "播放"}

func (a *App) newWeekCommand() *cobra.Command {
	var group string
	command := &cobra.Command{
		Use:   "week",
		Short: "查看新番时间表",
		Long: `查看首页的新番时间表.

站点把周日到周六, 剧场与天朝共九个分组渲染在首页里, 这里一次取回全部,
--group 可以只显示其中一个.`,
		Args: cobra.NoArgs,
		RunE: func(command *cobra.Command, _ []string) error {
			client, err := a.clientOrErr()
			if err != nil {
				return a.fail(command, err, "")
			}
			groups, err := client.WeekTable(command.Context())
			if err != nil {
				return a.fail(command, err, "获取新番时间表")
			}
			filtered := filterWeekGroups(groups, group)
			if len(filtered) == 0 {
				return a.fail(command, api.NewError(api.CodeNotFound, "获取新番时间表", "没有找到对应分组"), "")
			}
			return a.finish(command, map[string]any{"groups": filtered}, func(mode output.Mode) {
				for index, item := range filtered {
					if index > 0 {
						a.Out.Line(mode, "")
					}
					a.Out.RenderTable(mode, item.Title, weekHeaders, weekRows(item.Items))
				}
			})
		},
	}
	command.Flags().StringVar(&group, "group", "", "只看某个分组, 例如 周一")
	return command
}

func filterWeekGroups(groups []model.WeekGroup, group string) []model.WeekGroup {
	if group == "" {
		return groups
	}
	result := make([]model.WeekGroup, 0, 1)
	for _, item := range groups {
		if item.Title == group {
			result = append(result, item)
		}
	}
	return result
}

func weekRows(items []model.Video) [][]string {
	rows := make([][]string, 0, len(items))
	for _, item := range items {
		rows = append(rows, []string{
			item.HID,
			item.Title,
			item.State,
			item.Tags,
			humanCount(item.PlayCount),
		})
	}
	return rows
}

func (a *App) newHomeCommand() *cobra.Command {
	command := &cobra.Command{
		Use:   "home",
		Short: "查看首页概览",
		Long: `查看站点首页概览.

包含站点实时在线人数, 首页广告位, 分区树与首页的新番时间表.
时间表与广告位来自同一份首页, 只请求一次.`,
		Args: cobra.NoArgs,
		RunE: func(command *cobra.Command, _ []string) error {
			client, err := a.clientOrErr()
			if err != nil {
				return a.fail(command, err, "")
			}
			week, ads, err := client.HomePage(command.Context())
			if err != nil {
				return a.fail(command, err, "获取首页")
			}
			online, players, err := client.SiteOnline(command.Context())
			if err != nil {
				a.Logger.Warn("读取站点在线人数失败", "error", err)
			}
			payload := map[string]any{
				"site_online": map[string]any{"online": online, "players": players},
				"channels":    channelTree,
				"week":        week,
				"ads":         ads,
			}
			return a.finish(command, payload, func(mode output.Mode) {
				if online != nil || players != nil {
					a.Out.Line(mode, "站点在线: %s   在线播放器: %s", countText(online), countText(players))
				}
				if len(ads) > 0 {
					rows := make([][]string, 0, len(ads))
					for _, ad := range ads {
						rows = append(rows, []string{ad.LinkURL, ad.ImageURL})
					}
					a.Out.RenderTable(mode, "首页广告位", []string{"链接", "图片"}, rows)
				}
				a.renderChannels(mode, channelTree)
				for _, group := range week {
					if len(group.Items) == 0 {
						continue
					}
					a.Out.RenderTable(mode, "新番时间表 - "+group.Title, weekHeaders, weekRows(group.Items))
				}
			})
		},
	}
	return command
}

func (a *App) newAdCommand() *cobra.Command {
	return &cobra.Command{
		Use:   "ad",
		Short: "列出首页广告位",
		Args:  cobra.NoArgs,
		RunE: func(command *cobra.Command, _ []string) error {
			client, err := a.clientOrErr()
			if err != nil {
				return a.fail(command, err, "")
			}
			items, err := client.Ads(command.Context())
			if err != nil {
				return a.fail(command, err, "获取广告位")
			}
			return a.finish(command, map[string]any{"items": items}, func(mode output.Mode) {
				if len(items) == 0 {
					a.Out.Line(mode, "首页没有广告位")
					return
				}
				rows := make([][]string, 0, len(items))
				for _, ad := range items {
					rows = append(rows, []string{ad.LinkURL, ad.ImageURL})
				}
				a.Out.RenderTable(mode, "首页广告位", []string{"链接", "图片"}, rows)
			})
		},
	}
}
