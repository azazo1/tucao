package cli

import (
	"strconv"

	"github.com/azazo1/tucao/cli/internal/model"
	"github.com/azazo1/tucao/cli/internal/output"
)

// videoHeaders 是视频列表表格的列.
var videoHeaders = []string{"编号", "标题", "分区", "播放", "弹幕", "UP主", "发布时间"}

// videoRows 把视频列表转成表格行.
func videoRows(items []model.Video) [][]string {
	rows := make([][]string, 0, len(items))
	for _, item := range items {
		rows = append(rows, []string{
			item.HID,
			item.Title,
			item.TypeName,
			humanCount(item.PlayCount),
			humanCount(item.DanmakuCount),
			item.UserName,
			shortDate(item.CreateAt),
		})
	}
	return rows
}

// renderVideoList 输出视频列表.
func (a *App) renderVideoList(mode output.Mode, title string, list *model.VideoList) {
	if mode != output.ModeRich || list == nil {
		return
	}
	a.Out.Line(mode, "共 %d 条, 第 %d 页", list.Total, list.Page)
	a.Out.RenderTable(mode, title, videoHeaders, videoRows(list.Items))
	if list.HasMore {
		a.Out.Line(mode, "还有下一页, 加 --page %d 继续", list.Page+1)
	}
}

// shortDate 取时间文本里的日期部分.
func shortDate(text string) string {
	if len(text) >= 10 {
		return text[:10]
	}
	return text
}

// renderRankGroups 输出按时段或分类分组的榜单.
func (a *App) renderRankGroups(mode output.Mode, title string, groups []model.RankGroup) {
	if mode != output.ModeRich {
		return
	}
	for index, group := range groups {
		heading := title
		if group.Title != "" {
			heading = title + " - " + group.Title
		}
		if index > 0 {
			a.Out.Line(mode, "")
		}
		a.Out.RenderTable(mode, heading, videoHeaders, videoRows(group.Items))
	}
}

// numberText 把可空的数字转成表格文本.
func numberText(value *int) string {
	if value == nil {
		return "-"
	}
	return strconv.Itoa(*value)
}

// countText 把可空的数字按大数习惯显示.
func countText(value *int) string {
	if value == nil {
		return "-"
	}
	return humanCount(*value)
}
