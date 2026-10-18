package cli

import (
	"strconv"
	"time"

	"github.com/spf13/cobra"

	"github.com/azazo1/tucao/cli/internal/api"
	"github.com/azazo1/tucao/cli/internal/model"
	"github.com/azazo1/tucao/cli/internal/output"
	"github.com/azazo1/tucao/cli/internal/store"
)

func (a *App) newFavCommand() *cobra.Command {
	command := &cobra.Command{
		Use:   "fav",
		Short: "管理本地收藏",
		Long: `管理本地收藏.

本地收藏只存在本机, 不与站点账号同步, 这一点与安卓端一致;
写进站点账号的是 tucao video favorite.`,
		Args: cobra.NoArgs,
		RunE: func(command *cobra.Command, _ []string) error {
			return a.runFavList(command)
		},
	}
	command.AddCommand(a.newFavListCommand(), a.newFavAddCommand(), a.newFavRemoveCommand(), a.newFavToggleCommand())
	return command
}

func (a *App) favStore() (*store.Store, *store.Favorites, error) {
	dataStore, err := a.dataOrErr()
	if err != nil {
		return nil, nil, err
	}
	favorites, err := dataStore.LoadFavorites()
	if err != nil {
		return nil, nil, api.WrapError(api.CodeInternal, "读取本地收藏", err.Error(), err)
	}
	return dataStore, favorites, nil
}

func (a *App) runFavList(command *cobra.Command) error {
	_, favorites, err := a.favStore()
	if err != nil {
		return a.fail(command, err, "")
	}
	return a.finish(command, map[string]any{
		"total": len(favorites.Items),
		"items": favorites.Items,
	}, func(mode output.Mode) {
		if len(favorites.Items) == 0 {
			a.Out.Line(mode, "本地收藏为空")
			return
		}
		rows := make([][]string, 0, len(favorites.Items))
		for _, item := range favorites.Items {
			rows = append(rows, []string{
				item.Video.HID,
				item.Video.Title,
				item.Video.TypeName,
				time.Unix(item.SavedAt, 0).Format("2006-01-02"),
			})
		}
		a.Out.RenderTable(mode, "本地收藏", []string{"编号", "标题", "分区", "收藏时间"}, rows)
	})
}

func (a *App) newFavListCommand() *cobra.Command {
	return &cobra.Command{
		Use:   "list",
		Short: "列出本地收藏",
		Args:  cobra.NoArgs,
		RunE: func(command *cobra.Command, _ []string) error {
			return a.runFavList(command)
		},
	}
}

func (a *App) newFavAddCommand() *cobra.Command {
	return &cobra.Command{
		Use:   "add 视频编号",
		Short: "加入本地收藏",
		Args:  cobra.ExactArgs(1),
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
			dataStore, favorites, err := a.favStore()
			if err != nil {
				return a.fail(command, err, "")
			}
			added := favorites.Add(*video, time.Now().Unix())
			if added {
				if err := dataStore.SaveFavorites(favorites); err != nil {
					return a.fail(command, api.WrapError(api.CodeInternal, "保存本地收藏", err.Error(), err), "")
				}
			}
			return a.finish(command, map[string]any{
				"hid":   video.HID,
				"title": video.Title,
				"added": added,
				"total": len(favorites.Items),
			}, func(mode output.Mode) {
				if added {
					a.Out.Line(mode, "已加入本地收藏: %s", video.Title)
					return
				}
				a.Out.Line(mode, "已在本地收藏里: %s", video.Title)
			})
		},
	}
}

func (a *App) newFavRemoveCommand() *cobra.Command {
	var yes bool
	command := &cobra.Command{
		Use:   "rm 视频编号",
		Short: "删除本地收藏",
		Args:  cobra.ExactArgs(1),
		RunE: func(command *cobra.Command, args []string) error {
			hid, err := parseHID(args[0])
			if err != nil {
				return a.invalidInput(command, err.Error())
			}
			if err := a.requireDestructive("删除本地收藏", yes); err != nil {
				return a.fail(command, err, "")
			}
			dataStore, favorites, err := a.favStore()
			if err != nil {
				return a.fail(command, err, "")
			}
			if !favorites.Remove(hid) {
				return a.fail(command, api.NewError(api.CodeNotFound, "删除本地收藏", "收藏里没有 "+hid), "")
			}
			if err := dataStore.SaveFavorites(favorites); err != nil {
				return a.fail(command, api.WrapError(api.CodeInternal, "保存本地收藏", err.Error(), err), "")
			}
			return a.finish(command, map[string]any{
				"hid":   hid,
				"total": len(favorites.Items),
			}, func(mode output.Mode) {
				a.Out.Line(mode, "已从本地收藏删除 %s", hid)
			})
		},
	}
	command.Flags().BoolVar(&yes, "yes", false, "确认删除")
	return command
}

func (a *App) newFavToggleCommand() *cobra.Command {
	return &cobra.Command{
		Use:   "toggle 视频编号",
		Short: "在收藏与取消之间切换",
		Args:  cobra.ExactArgs(1),
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
			dataStore, favorites, err := a.favStore()
			if err != nil {
				return a.fail(command, err, "")
			}
			favorited := true
			if favorites.Remove(hid) {
				favorited = false
			} else {
				favorites.Add(*video, time.Now().Unix())
			}
			if err := dataStore.SaveFavorites(favorites); err != nil {
				return a.fail(command, api.WrapError(api.CodeInternal, "保存本地收藏", err.Error(), err), "")
			}
			return a.finish(command, map[string]any{
				"hid":       hid,
				"favorited": favorited,
				"total":     len(favorites.Items),
			}, func(mode output.Mode) {
				if favorited {
					a.Out.Line(mode, "已加入本地收藏: %s", video.Title)
					return
				}
				a.Out.Line(mode, "已从本地收藏删除: %s", video.Title)
			})
		},
	}
}

func (a *App) newHistoryCommand() *cobra.Command {
	command := &cobra.Command{
		Use:   "history",
		Short: "管理本地播放历史",
		Long: `管理本地播放历史.

命令行工具没有播放器, 因此不会自动产生进度; tucao history add 供脚本写入,
其余子命令用来查看与清理. 搜索历史在 tucao history search 下.`,
		Args: cobra.NoArgs,
		RunE: func(command *cobra.Command, _ []string) error {
			return a.runHistoryList(command, "")
		},
	}
	command.AddCommand(a.newHistoryListCommand(), a.newHistoryAddCommand(),
		a.newHistoryRemoveCommand(), a.newHistoryClearCommand(), a.newSearchHistoryCommand())
	return command
}

func (a *App) loadHistory() (*store.Store, *store.History, error) {
	dataStore, err := a.dataOrErr()
	if err != nil {
		return nil, nil, err
	}
	history, err := dataStore.LoadHistory()
	if err != nil {
		return nil, nil, api.WrapError(api.CodeInternal, "读取播放历史", err.Error(), err)
	}
	return dataStore, history, nil
}

func (a *App) runHistoryList(command *cobra.Command, hid string) error {
	_, history, err := a.loadHistory()
	if err != nil {
		return a.fail(command, err, "")
	}
	items := history.Items
	if hid != "" {
		filtered := make([]store.HistoryItem, 0, 1)
		for _, item := range items {
			if item.Video.HID == hid {
				filtered = append(filtered, item)
			}
		}
		items = filtered
	}
	return a.finish(command, map[string]any{
		"total": len(items),
		"items": items,
	}, func(mode output.Mode) {
		if len(items) == 0 {
			a.Out.Line(mode, "播放历史为空")
			return
		}
		rows := make([][]string, 0, len(items))
		for _, item := range items {
			rows = append(rows, []string{
				item.Video.HID,
				strconv.Itoa(item.Part + 1),
				item.Video.Title,
				formatDuration(item.Progress) + " / " + formatDuration(item.Duration),
				time.UnixMilli(item.UpdateTime).Format("2006-01-02 15:04"),
			})
		}
		a.Out.RenderTable(mode, "播放历史", []string{"编号", "分P", "标题", "进度", "更新时间"}, rows)
	})
}

func (a *App) newHistoryListCommand() *cobra.Command {
	return &cobra.Command{
		Use:   "list [视频编号]",
		Short: "列出播放历史",
		Args:  cobra.MaximumNArgs(1),
		RunE: func(command *cobra.Command, args []string) error {
			hid := ""
			if len(args) == 1 {
				value, err := parseHID(args[0])
				if err != nil {
					return a.invalidInput(command, err.Error())
				}
				hid = value
			}
			return a.runHistoryList(command, hid)
		},
	}
}

func (a *App) newHistoryAddCommand() *cobra.Command {
	var (
		part     float64
		progress float64
		duration float64
	)
	command := &cobra.Command{
		Use:   "add 视频编号",
		Short: "写入一条播放记录",
		Long:  "供脚本或 agent 写入进度, 视频信息会从站点详情接口取回.",
		Args:  cobra.ExactArgs(1),
		RunE: func(command *cobra.Command, args []string) error {
			hid, err := parseHID(args[0])
			if err != nil {
				return a.invalidInput(command, err.Error())
			}
			index := int(part) - 1
			if index < 0 {
				return a.invalidInput(command, "分P序号必须是从 1 开始的整数")
			}
			client, err := a.clientOrErr()
			if err != nil {
				return a.fail(command, err, "")
			}
			video, err := client.VideoView(command.Context(), hid)
			if err != nil {
				return a.fail(command, err, "获取视频详情")
			}
			dataStore, history, err := a.loadHistory()
			if err != nil {
				return a.fail(command, err, "")
			}
			history.Record(store.HistoryItem{
				Video:      *video,
				Part:       index,
				Progress:   progress,
				Duration:   duration,
				UpdateTime: time.Now().UnixMilli(),
			}, a.Config.History.Limit)
			if err := dataStore.SaveHistory(history); err != nil {
				return a.fail(command, api.WrapError(api.CodeInternal, "保存播放历史", err.Error(), err), "")
			}
			return a.finish(command, map[string]any{
				"hid":   hid,
				"part":  index + 1,
				"total": len(history.Items),
			}, func(mode output.Mode) {
				a.Out.Line(mode, "已记录 %s 第 %d 分P的进度", hid, index+1)
			})
		},
	}
	command.Flags().Float64Var(&part, "part", 1, "分P序号, 从 1 开始")
	command.Flags().Float64Var(&progress, "progress", 0, "播放进度, 秒")
	command.Flags().Float64Var(&duration, "duration", 0, "视频总时长, 秒")
	return command
}

func (a *App) newHistoryRemoveCommand() *cobra.Command {
	var (
		part int
		yes  bool
	)
	command := &cobra.Command{
		Use:   "rm 视频编号",
		Short: "删除播放记录",
		Long:  "不加 --part 时删除该视频的全部分P记录.",
		Args:  cobra.ExactArgs(1),
		RunE: func(command *cobra.Command, args []string) error {
			hid, err := parseHID(args[0])
			if err != nil {
				return a.invalidInput(command, err.Error())
			}
			if err := a.requireDestructive("删除播放记录", yes); err != nil {
				return a.fail(command, err, "")
			}
			dataStore, history, err := a.loadHistory()
			if err != nil {
				return a.fail(command, err, "")
			}
			index := -1
			if part > 0 {
				index = part - 1
			}
			removed := history.Remove(hid, index)
			if removed == 0 {
				return a.fail(command, api.NewError(api.CodeNotFound, "删除播放记录", "没有找到对应的记录"), "")
			}
			if err := dataStore.SaveHistory(history); err != nil {
				return a.fail(command, api.WrapError(api.CodeInternal, "保存播放历史", err.Error(), err), "")
			}
			return a.finish(command, map[string]any{
				"hid":     hid,
				"removed": removed,
				"total":   len(history.Items),
			}, func(mode output.Mode) {
				a.Out.Line(mode, "已删除 %d 条播放记录", removed)
			})
		},
	}
	command.Flags().IntVar(&part, "part", 0, "只删除该分P, 从 1 开始")
	command.Flags().BoolVar(&yes, "yes", false, "确认删除")
	return command
}

func (a *App) newHistoryClearCommand() *cobra.Command {
	var yes bool
	command := &cobra.Command{
		Use:   "clear",
		Short: "清空播放历史",
		Args:  cobra.NoArgs,
		RunE: func(command *cobra.Command, _ []string) error {
			if err := a.requireDestructive("清空播放历史", yes); err != nil {
				return a.fail(command, err, "")
			}
			dataStore, history, err := a.loadHistory()
			if err != nil {
				return a.fail(command, err, "")
			}
			removed := len(history.Items)
			history.Items = nil
			if err := dataStore.SaveHistory(history); err != nil {
				return a.fail(command, api.WrapError(api.CodeInternal, "保存播放历史", err.Error(), err), "")
			}
			return a.finish(command, map[string]any{"removed": removed}, func(mode output.Mode) {
				a.Out.Line(mode, "已清空 %d 条播放记录", removed)
			})
		},
	}
	command.Flags().BoolVar(&yes, "yes", false, "确认清空")
	return command
}

func (a *App) newSearchHistoryCommand() *cobra.Command {
	command := &cobra.Command{
		Use:   "search",
		Short: "管理本地搜索历史",
		Args:  cobra.NoArgs,
		RunE: func(command *cobra.Command, _ []string) error {
			return a.runSearchHistoryList(command)
		},
	}
	command.AddCommand(
		&cobra.Command{
			Use:   "list",
			Short: "列出搜索历史",
			Args:  cobra.NoArgs,
			RunE: func(command *cobra.Command, _ []string) error {
				return a.runSearchHistoryList(command)
			},
		},
		a.newSearchHistoryRemoveCommand(),
		a.newSearchHistoryClearCommand(),
	)
	return command
}

func (a *App) runSearchHistoryList(command *cobra.Command) error {
	dataStore, err := a.dataOrErr()
	if err != nil {
		return a.fail(command, err, "")
	}
	history, err := dataStore.LoadSearchHistory()
	if err != nil {
		return a.fail(command, api.WrapError(api.CodeInternal, "读取搜索历史", err.Error(), err), "")
	}
	return a.finish(command, map[string]any{
		"total": len(history.Items),
		"items": history.Items,
	}, func(mode output.Mode) {
		if len(history.Items) == 0 {
			a.Out.Line(mode, "搜索历史为空")
			return
		}
		for index, keyword := range history.Items {
			a.Out.Line(mode, "%d. %s", index+1, keyword)
		}
	})
}

func (a *App) newSearchHistoryRemoveCommand() *cobra.Command {
	var yes bool
	command := &cobra.Command{
		Use:   "rm 关键词",
		Short: "删除一条搜索历史",
		Args:  cobra.ExactArgs(1),
		RunE: func(command *cobra.Command, args []string) error {
			if err := a.requireDestructive("删除搜索历史", yes); err != nil {
				return a.fail(command, err, "")
			}
			dataStore, err := a.dataOrErr()
			if err != nil {
				return a.fail(command, err, "")
			}
			history, err := dataStore.LoadSearchHistory()
			if err != nil {
				return a.fail(command, api.WrapError(api.CodeInternal, "读取搜索历史", err.Error(), err), "")
			}
			if !history.Remove(args[0]) {
				return a.fail(command, api.NewError(api.CodeNotFound, "删除搜索历史", "没有找到该关键词"), "")
			}
			if err := dataStore.SaveSearchHistory(history); err != nil {
				return a.fail(command, api.WrapError(api.CodeInternal, "保存搜索历史", err.Error(), err), "")
			}
			return a.finish(command, map[string]any{"keyword": args[0], "total": len(history.Items)}, func(mode output.Mode) {
				a.Out.Line(mode, "已删除搜索历史: %s", args[0])
			})
		},
	}
	command.Flags().BoolVar(&yes, "yes", false, "确认删除")
	return command
}

func (a *App) newSearchHistoryClearCommand() *cobra.Command {
	var yes bool
	command := &cobra.Command{
		Use:   "clear",
		Short: "清空搜索历史",
		Args:  cobra.NoArgs,
		RunE: func(command *cobra.Command, _ []string) error {
			if err := a.requireDestructive("清空搜索历史", yes); err != nil {
				return a.fail(command, err, "")
			}
			dataStore, err := a.dataOrErr()
			if err != nil {
				return a.fail(command, err, "")
			}
			history, err := dataStore.LoadSearchHistory()
			if err != nil {
				return a.fail(command, api.WrapError(api.CodeInternal, "读取搜索历史", err.Error(), err), "")
			}
			removed := len(history.Items)
			history.Items = nil
			if err := dataStore.SaveSearchHistory(history); err != nil {
				return a.fail(command, api.WrapError(api.CodeInternal, "保存搜索历史", err.Error(), err), "")
			}
			return a.finish(command, map[string]any{"removed": removed}, func(mode output.Mode) {
				a.Out.Line(mode, "已清空 %d 条搜索历史", removed)
			})
		},
	}
	command.Flags().BoolVar(&yes, "yes", false, "确认清空")
	return command
}

func (a *App) newUpdateCommand() *cobra.Command {
	command := &cobra.Command{
		Use:   "update",
		Short: "检查新版本",
		Args:  cobra.NoArgs,
		RunE: func(command *cobra.Command, _ []string) error {
			return a.runUpdateCheck(command)
		},
	}
	command.AddCommand(&cobra.Command{
		Use:   "check",
		Short: "检查 GitHub 上的最新发布",
		Args:  cobra.NoArgs,
		RunE: func(command *cobra.Command, _ []string) error {
			return a.runUpdateCheck(command)
		},
	})
	return command
}

func (a *App) runUpdateCheck(command *cobra.Command) error {
	release, err := api.GitHubLatest(command.Context())
	if err != nil {
		return a.fail(command, err, "检查更新")
	}
	newer := !release.Prerelease && model.IsNewer(Version, release.TagName)
	return a.finish(command, map[string]any{
		"current":      Version,
		"latest":       release.TagName,
		"is_newer":     newer,
		"prerelease":   release.Prerelease,
		"page_url":     release.PageURL,
		"published_at": release.PublishedAt,
		"body":         release.Body,
	}, func(mode output.Mode) {
		a.Out.Line(mode, "当前版本: %s", Version)
		a.Out.Line(mode, "最新发布: %s", release.TagName)
		if newer {
			a.Out.Line(mode, "有新版本, 发布页: %s", release.PageURL)
		} else {
			a.Out.Line(mode, "已是最新版本")
		}
		if release.Body != "" {
			a.Out.Line(mode, "")
			a.Out.Line(mode, "%s", release.Body)
		}
	})
}
