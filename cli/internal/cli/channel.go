package cli

import (
	"strconv"
	"strings"

	"github.com/spf13/cobra"

	"github.com/azazo1/tucao/cli/internal/output"
)

// Channel 是站点分区.
type Channel struct {
	ID       int       `json:"id" yaml:"id"`
	Name     string    `json:"name" yaml:"name"`
	Children []Channel `json:"children,omitempty" yaml:"children,omitempty"`
}

// channelTree 是首页固定分区树, 与官网导航保持一致.
var channelTree = []Channel{
	{ID: 24, Name: "新番", Children: []Channel{
		{ID: 11, Name: "连载新番"},
		{ID: 43, Name: "天朝出品"},
		{ID: 26, Name: "剧场版"},
		{ID: 10, Name: "完结番组"},
	}},
	{ID: 23, Name: "影剧", Children: []Channel{
		{ID: 39, Name: "电视剧"},
		{ID: 38, Name: "电影"},
		{ID: 16, Name: "综艺娱乐"},
	}},
	{ID: 19, Name: "综合", Children: []Channel{
		{ID: 28, Name: "动画"},
		{ID: 6, Name: "音乐"},
		{ID: 29, Name: "游戏"},
	}},
}

// allChannels 返回顶级分区与全部子分区.
func allChannels() []Channel {
	result := make([]Channel, 0, len(channelTree)*2)
	for _, channel := range channelTree {
		result = append(result, Channel{ID: channel.ID, Name: channel.Name})
		result = append(result, channel.Children...)
	}
	return result
}

// findChannel 按分区编号或名字查找分区, 名字允许使用子分区名.
func findChannel(raw string) (Channel, bool) {
	text := strings.TrimSpace(raw)
	if text == "" {
		return Channel{}, false
	}
	if id, err := strconv.Atoi(text); err == nil {
		for _, channel := range allChannels() {
			if channel.ID == id {
				return channel, true
			}
		}
		return Channel{}, false
	}
	for _, channel := range allChannels() {
		if channel.Name == text {
			return channel, true
		}
	}
	return Channel{}, false
}

func (a *App) newChannelCommand() *cobra.Command {
	command := &cobra.Command{
		Use:   "channel [分区]",
		Short: "列出站点分区, 或查看某个分区",
		Long: `列出站点分区树, 或查看某个分区.

分区可以用编号或名字指定, 名字同时支持顶级分区与子分区.`,
		Args: cobra.MaximumNArgs(1),
		RunE: func(command *cobra.Command, args []string) error {
			if len(args) == 0 {
				return a.finish(command, map[string]any{"channels": channelTree}, func(mode output.Mode) {
					a.renderChannels(mode, channelTree)
				})
			}
			channel, ok := findChannel(args[0])
			if !ok {
				return a.invalidInput(command, "未知分区: "+args[0])
			}
			return a.finish(command, channel, func(mode output.Mode) {
				rows := [][]string{{strconv.Itoa(channel.ID), channel.Name}}
				for _, child := range channel.Children {
					rows = append(rows, []string{strconv.Itoa(child.ID), child.Name})
				}
				a.Out.RenderTable(mode, "分区 "+channel.Name, []string{"编号", "名称"}, rows)
			})
		},
	}
	return command
}

func (a *App) renderChannels(mode output.Mode, channels []Channel) {
	rows := make([][]string, 0, len(channels))
	for _, channel := range channels {
		rows = append(rows, []string{strconv.Itoa(channel.ID), channel.Name, ""})
		for _, child := range channel.Children {
			rows = append(rows, []string{strconv.Itoa(child.ID), child.Name, channel.Name})
		}
	}
	a.Out.RenderTable(mode, "站点分区", []string{"编号", "名称", "父分区"}, rows)
}
