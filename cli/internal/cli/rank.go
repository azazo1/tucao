package cli

import (
	"strconv"
	"strings"

	"github.com/spf13/cobra"

	"github.com/azazo1/tucao/cli/internal/api"
	"github.com/azazo1/tucao/cli/internal/model"
	"github.com/azazo1/tucao/cli/internal/output"
)

// periodNames 是时间维度参数与 period 值的对应关系.
var periodNames = map[string]int{
	"today": 0,
	"week":  1,
	"month": 2,
	"year":  3,
	"今天":    0,
	"本周":    1,
	"本月":    2,
	"今年":    3,
}

func parsePeriod(raw string) (int, error) {
	text := strings.ToLower(strings.TrimSpace(raw))
	if text == "" {
		return 0, nil
	}
	if value, ok := periodNames[text]; ok {
		return value, nil
	}
	return 0, api.NewError(api.CodeInvalidInput, "", "时间维度只支持 today, week, month 与 year")
}

// rankTypeKeys 列出全部榜单标识, 用于报错提示.
func rankTypeKeys() string {
	keys := make([]string, 0, len(api.RankTypes))
	for _, rankType := range api.RankTypes {
		keys = append(keys, rankType.Key)
	}
	return strings.Join(keys, ", ")
}

func (a *App) newRankCommand() *cobra.Command {
	var (
		typeName string
		channel  string
		period   string
	)
	command := &cobra.Command{
		Use:   "rank",
		Short: "查看各类榜单",
		Long: `查看排行, 弹幕, 神评论, 无人区, 追番, 在线, 今天更新与今天推荐等榜单.

榜单页面按 今天 / 本周 / 本月 / 今年 分组, --period 只影响站点返回的默认维度,
输出里仍然包含页面上出现的全部分组.

热搜榜与 u 榜结构不同, 分别是 tucao rank hot-search 与 tucao rank user.`,
		Args: cobra.NoArgs,
		RunE: func(command *cobra.Command, _ []string) error {
			rankType, ok := api.FindRankType(typeName)
			if !ok {
				return a.invalidInput(command, "未知榜单: "+typeName+", 可选 "+rankTypeKeys())
			}
			typeID, err := resolveChannelRef(channel)
			if err != nil {
				return a.fail(command, err, "")
			}
			if typeID > 0 && !rankType.SupportsChannel {
				return a.invalidInput(command, rankType.Label+"不支持按分区筛选")
			}
			periodValue, err := parsePeriod(period)
			if err != nil {
				return a.fail(command, err, "")
			}
			client, err := a.clientOrErr()
			if err != nil {
				return a.fail(command, err, "")
			}
			groups, err := client.Rank(command.Context(), rankType, typeID, periodValue)
			if err != nil {
				return a.fail(command, err, "获取"+rankType.Label)
			}
			payload := map[string]any{
				"type":    rankType.Key,
				"label":   rankType.Label,
				"period":  period,
				"channel": typeID,
				"groups":  groups,
			}
			return a.finish(command, payload, func(mode output.Mode) {
				a.renderRankGroups(mode, rankType.Label, groups)
			})
		},
	}
	command.Flags().StringVarP(&typeName, "type", "t", "hot", "榜单类型: "+rankTypeKeys())
	command.Flags().StringVarP(&channel, "channel", "c", "", "分区编号或名字, 只有排行榜支持")
	command.Flags().StringVarP(&period, "period", "p", "today", "默认时间维度: today, week, month, year")
	command.AddCommand(a.newHotSearchCommand(), a.newUserRankCommand())
	return command
}

func (a *App) newHotSearchCommand() *cobra.Command {
	var (
		limit int
		group string
	)
	command := &cobra.Command{
		Use:   "hot-search",
		Short: "查看热搜榜",
		Args:  cobra.NoArgs,
		RunE: func(command *cobra.Command, _ []string) error {
			client, err := a.clientOrErr()
			if err != nil {
				return a.fail(command, err, "")
			}
			groups, err := client.HotSearch(command.Context())
			if err != nil {
				return a.fail(command, err, "获取热搜榜")
			}
			groups = filterHotSearch(groups, group, limit)
			if len(groups) == 0 {
				return a.fail(command, api.NewError(api.CodeNotFound, "获取热搜榜", "没有找到对应的热搜分组"), "")
			}
			return a.finish(command, map[string]any{"groups": groups}, func(mode output.Mode) {
				for index, item := range groups {
					if index > 0 {
						a.Out.Line(mode, "")
					}
					rows := make([][]string, 0, len(item.Items))
					for _, keyword := range item.Items {
						rows = append(rows, []string{strconv.Itoa(keyword.Rank), keyword.Keyword, strconv.Itoa(keyword.Count)})
					}
					a.Out.RenderTable(mode, "热搜榜 - "+item.Title, []string{"排名", "关键词", "搜索次数"}, rows)
				}
			})
		},
	}
	command.Flags().IntVar(&limit, "limit", 0, "每个分组最多显示多少条, 0 表示不限制")
	command.Flags().StringVar(&group, "group", "", "只看某个分组, 例如 今天")
	return command
}

// filterHotSearch 按分组名与条数上限裁剪热搜榜.
func filterHotSearch(groups []model.HotSearchGroup, group string, limit int) []model.HotSearchGroup {
	result := make([]model.HotSearchGroup, 0, len(groups))
	for _, item := range groups {
		if group != "" && item.Title != group {
			continue
		}
		if limit > 0 && len(item.Items) > limit {
			item.Items = item.Items[:limit]
		}
		result = append(result, item)
	}
	return result
}

func (a *App) newUserRankCommand() *cobra.Command {
	var (
		group string
		limit int
	)
	command := &cobra.Command{
		Use:   "user",
		Short: "查看 u 榜",
		Long: `查看按用户维度排名的 u 榜.

条目里的用户编号可以直接给 tucao space 用来查看用户空间.`,
		Args: cobra.NoArgs,
		RunE: func(command *cobra.Command, _ []string) error {
			client, err := a.clientOrErr()
			if err != nil {
				return a.fail(command, err, "")
			}
			groups, err := client.UserRank(command.Context())
			if err != nil {
				return a.fail(command, err, "获取 u 榜")
			}
			filtered := make([]model.UserRankGroup, 0, len(groups))
			for _, item := range groups {
				if group != "" && item.Title != group {
					continue
				}
				if limit > 0 && len(item.Items) > limit {
					item.Items = item.Items[:limit]
				}
				filtered = append(filtered, item)
			}
			if len(filtered) == 0 {
				return a.fail(command, api.NewError(api.CodeNotFound, "获取 u 榜", "没有找到对应的分组"), "")
			}
			return a.finish(command, map[string]any{"groups": filtered}, func(mode output.Mode) {
				for index, item := range filtered {
					if index > 0 {
						a.Out.Line(mode, "")
					}
					rows := make([][]string, 0, len(item.Items))
					for _, user := range item.Items {
						rows = append(rows, []string{
							strconv.Itoa(user.Rank),
							user.UserName,
							strconv.Itoa(user.UserID),
							user.Badge,
						})
					}
					a.Out.RenderTable(mode, "u 榜 - "+item.Title, []string{"排名", "用户", "编号", "标签"}, rows)
				}
			})
		},
	}
	command.Flags().StringVar(&group, "group", "", "只看某个分组")
	command.Flags().IntVar(&limit, "limit", 0, "每个分组最多显示多少条, 0 表示不限制")
	return command
}
