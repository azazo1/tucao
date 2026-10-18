package cli

import (
	"context"
	"strconv"
	"sync"

	"github.com/spf13/cobra"

	"github.com/azazo1/tucao/cli/internal/api"
	"github.com/azazo1/tucao/cli/internal/model"
	"github.com/azazo1/tucao/cli/internal/output"
)

// itoaPlain 是 strconv.Itoa 的短别名.
func itoaPlain(value int) string { return strconv.Itoa(value) }

func (a *App) newVideoCommand() *cobra.Command {
	var noStats bool
	command := &cobra.Command{
		Use:   "video 视频编号",
		Short: "查看视频详情",
		Long: `查看视频详情.

视频编号接受 4107860, h4107860 或完整的播放页地址.
详情默认附带播放页完整简介, 番组信息与四项统计; 加 --no-stats 可跳过统计.`,
		Args: cobra.ExactArgs(1),
		RunE: func(command *cobra.Command, args []string) error {
			hid, err := parseHID(args[0])
			if err != nil {
				return a.invalidInput(command, err.Error())
			}
			client, err := a.clientOrErr()
			if err != nil {
				return a.fail(command, err, "")
			}
			video, err := client.VideoView(command.Context(), hid)
			if err != nil {
				return a.fail(command, err, "获取视频详情")
			}
			detail := &model.VideoDetail{Video: *video}

			var waitGroup sync.WaitGroup
			waitGroup.Add(1)
			go func() {
				defer waitGroup.Done()
				page, pageErr := client.PlayPage(command.Context(), hid)
				if pageErr != nil {
					a.Logger.Warn("读取播放页附加信息失败", "error", pageErr)
					return
				}
				detail.FullDescription = page.Description
				detail.Subject = page.Subject
			}()
			if !noStats {
				waitGroup.Add(1)
				go func() {
					defer waitGroup.Done()
					detail.Stats = a.loadVideoStats(command.Context(), client, video.TypeID, hid)
				}()
			}
			waitGroup.Wait()

			return a.finish(command, detail, func(mode output.Mode) {
				a.renderVideoDetail(mode, detail)
			})
		},
	}
	command.Flags().BoolVar(&noStats, "no-stats", false, "不请求播放统计")
	command.AddCommand(a.newVideoDanmakuCommand(), a.newVideoCommentCommand(),
		a.newVideoFavoriteCommand(), a.newVideoDownloadCommand())
	return command
}

// loadVideoStats 并行取在线人数, 播放量, 追番数与评论数.
//
// 站点没有一次返回全部统计的接口, 各项分开取, 单项失败只让该字段为空.
func (a *App) loadVideoStats(ctx context.Context, client *api.Client, typeID int, hid string) *model.VideoStats {
	stats := &model.VideoStats{}
	var waitGroup sync.WaitGroup

	waitGroup.Add(3)
	go func() {
		defer waitGroup.Done()
		value, err := client.OnlineCount(ctx, hid, api.VideoModelID)
		if err != nil {
			a.Logger.Debug("读取在线人数失败", "error", err)
			return
		}
		stats.OnlineCount = value
	}()
	go func() {
		defer waitGroup.Done()
		playCount, favoriteCount, err := client.ContentCounts(ctx, hid, api.VideoModelID)
		if err != nil {
			a.Logger.Debug("读取播放与追番数失败", "error", err)
			return
		}
		stats.PlayCount = playCount
		stats.FavoriteCount = favoriteCount
	}()
	go func() {
		defer waitGroup.Done()
		count, err := client.ReplyCount(ctx, typeID, hid)
		if err != nil {
			a.Logger.Debug("读取评论数失败", "error", err)
			return
		}
		stats.CommentCount = &count
	}()
	waitGroup.Wait()
	return stats
}

func (a *App) newVideoFavoriteCommand() *cobra.Command {
	return &cobra.Command{
		Use:   "favorite 视频编号",
		Short: "把视频加入站点收藏",
		Long: `调用站点的单向新增收藏接口.

这与本地收藏 (tucao fav) 是两件事: 站点收藏会写进账号, 安卓端只有实现与测试,
界面里没有入口; 本地收藏只存在本机.`,
		Args: cobra.ExactArgs(1),
		RunE: func(command *cobra.Command, args []string) error {
			hid, err := parseHID(args[0])
			if err != nil {
				return a.invalidInput(command, err.Error())
			}
			if err := a.requireWrite("加入站点收藏"); err != nil {
				return a.fail(command, err, "")
			}
			client, err := a.clientOrErr()
			if err != nil {
				return a.fail(command, err, "")
			}
			video, err := client.VideoView(command.Context(), hid)
			if err != nil {
				return a.fail(command, err, "获取视频详情")
			}
			if err := client.FavoriteAdd(command.Context(), *video); err != nil {
				return a.fail(command, err, "加入站点收藏")
			}
			return a.finish(command, map[string]any{
				"hid":       video.HID,
				"title":     video.Title,
				"site_url":  video.SiteURL,
				"favorited": true,
			}, func(mode output.Mode) {
				a.Out.Line(mode, "已加入站点收藏: %s", video.Title)
			})
		},
	}
}
