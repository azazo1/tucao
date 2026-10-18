package cli

import (
	"strconv"
	"strings"

	"github.com/spf13/cobra"

	"github.com/azazo1/tucao/cli/internal/api"
	"github.com/azazo1/tucao/cli/internal/model"
	"github.com/azazo1/tucao/cli/internal/output"
)

// bgmSeasonNames 是季度筛选项的可读写法.
var bgmSeasonNames = []string{"1月", "4月", "7月", "10月", "剧场版"}

func (a *App) newBgmCommand() *cobra.Command {
	var (
		season  string
		year    string
		types   string
		weekday string
		page    int
	)
	command := &cobra.Command{
		Use:   "bgm",
		Short: "查看番组索引",
		Long: `按季度, 年代, 题材与星期筛选番组.

季度用 1月 / 4月 / 7月 / 10月 / 剧场版, 星期用 星期一 到 星期日,
年代用 2026 或 2010-2019 这类写法. 都不传表示不限.`,
		Args: cobra.NoArgs,
		RunE: func(command *cobra.Command, _ []string) error {
			query := api.BgmQuery{Types: strings.TrimSpace(types), Page: page, Year: strings.TrimSpace(year)}
			if season != "" {
				month, err := parseSeason(season)
				if err != nil {
					return a.invalidInput(command, err.Error())
				}
				query.Month = month
			}
			if weekday != "" {
				value, err := parseWeekday(weekday)
				if err != nil {
					return a.invalidInput(command, err.Error())
				}
				query.Weekday = value
			}
			client, err := a.clientOrErr()
			if err != nil {
				return a.fail(command, err, "")
			}
			result, err := client.BgmIndex(command.Context(), query)
			if err != nil {
				return a.fail(command, err, "获取番组索引")
			}
			title := bgmTitle(season, year, types, weekday)
			return a.finish(command, result, func(mode output.Mode) {
				a.Out.Line(mode, "共 %d 条, 第 %d 页", result.Total, result.Page)
				a.Out.RenderTable(mode, "番组索引"+title, weekHeaders, weekRows(result.Items))
				if result.HasMore {
					a.Out.Line(mode, "还有下一页, 加 --page %d 继续", result.Page+1)
				}
			})
		},
	}
	command.Flags().StringVarP(&season, "season", "s", "", "季度: "+strings.Join(bgmSeasonNames, ", "))
	command.Flags().StringVar(&year, "year", "", "年代, 例如 2026 或 2010-2019")
	command.Flags().StringVar(&types, "types", "", "题材关键词")
	command.Flags().StringVarP(&weekday, "weekday", "w", "", "星期: 星期一 到 星期日")
	command.Flags().IntVar(&page, "page", 1, "页码, 从 1 开始")
	command.AddCommand(a.newBgmWeekCommand())
	return command
}

func bgmTitle(season, year, types, weekday string) string {
	parts := []string{}
	for _, value := range []string{season, year, types, weekday} {
		if strings.TrimSpace(value) != "" {
			parts = append(parts, strings.TrimSpace(value))
		}
	}
	if len(parts) == 0 {
		return ""
	}
	return " (" + strings.Join(parts, " / ") + ")"
}

func parseSeason(raw string) (int, error) {
	text := strings.TrimSpace(raw)
	if value, ok := api.BgmSeasons[text]; ok {
		return value, nil
	}
	if value, err := strconv.Atoi(text); err == nil {
		for _, season := range api.BgmSeasons {
			if season == value {
				return value, nil
			}
		}
	}
	return 0, api.NewError(api.CodeInvalidInput, "", "季度只支持 "+strings.Join(bgmSeasonNames, ", "))
}

func parseWeekday(raw string) (int, error) {
	text := strings.TrimSpace(raw)
	if value, ok := api.BgmWeekdays[text]; ok {
		return value, nil
	}
	if value, err := strconv.Atoi(text); err == nil && value >= 1 && value <= 7 {
		return value, nil
	}
	return 0, api.NewError(api.CodeInvalidInput, "", "星期只支持 星期一 到 星期日")
}

func (a *App) newBgmWeekCommand() *cobra.Command {
	var group string
	command := &cobra.Command{
		Use:   "week",
		Short: "查看本周新番",
		Long:  "按日期列出本周更新的番组, 与首页时间表是两份数据.",
		Args:  cobra.NoArgs,
		RunE: func(command *cobra.Command, _ []string) error {
			client, err := a.clientOrErr()
			if err != nil {
				return a.fail(command, err, "")
			}
			groups, err := client.WeekBgm(command.Context())
			if err != nil {
				return a.fail(command, err, "获取本周新番")
			}
			filtered := make([]model.WeekBgmGroup, 0, len(groups))
			for _, item := range groups {
				if group != "" && item.Title != group && item.Date != group {
					continue
				}
				filtered = append(filtered, item)
			}
			if len(filtered) == 0 {
				return a.fail(command, api.NewError(api.CodeNotFound, "获取本周新番", "没有找到对应日期分组"), "")
			}
			return a.finish(command, map[string]any{"groups": filtered}, func(mode output.Mode) {
				for index, item := range filtered {
					if index > 0 {
						a.Out.Line(mode, "")
					}
					a.Out.RenderTable(mode, item.Title, videoHeaders, videoRows(item.Items))
				}
			})
		},
	}
	command.Flags().StringVar(&group, "group", "", "只看某个日期分组, 例如 10-12 周一")
	return command
}
