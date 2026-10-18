package cli

import (
	"strings"

	"github.com/spf13/cobra"

	"github.com/azazo1/tucao/cli/internal/api"
	"github.com/azazo1/tucao/cli/internal/model"
	"github.com/azazo1/tucao/cli/internal/output"
)

func (a *App) newArticleCommand() *cobra.Command {
	var (
		page     int
		category string
	)
	command := &cobra.Command{
		Use:   "article",
		Short: "查看档案列表",
		Long: `查看站点的番组档案与资讯列表.

分类可以用 情报, 公告, 年鉴, anime, 动漫; 详情用 tucao article show 编号,
评论区用 tucao article comment 编号.`,
		Args: cobra.NoArgs,
		RunE: func(command *cobra.Command, _ []string) error {
			keyword := strings.TrimSpace(category)
			if keyword != "" && !isArticleCategory(keyword) {
				return a.invalidInput(command, "未知分类: "+keyword+", 可选 "+strings.Join(api.ArticleCategories, ", "))
			}
			return a.runArticleList(command, page, keyword)
		},
	}
	command.Flags().IntVar(&page, "page", 1, "页码, 从 1 开始")
	command.Flags().StringVarP(&category, "category", "c", "", "分类: "+strings.Join(api.ArticleCategories, ", "))
	command.AddCommand(a.newArticleListCommand(), a.newArticleShowCommand(), a.newArticleCommentCommand())
	return command
}

func isArticleCategory(value string) bool {
	for _, category := range api.ArticleCategories {
		if category == value {
			return true
		}
	}
	return false
}

func (a *App) newArticleListCommand() *cobra.Command {
	var (
		page     int
		category string
	)
	command := &cobra.Command{
		Use:   "list",
		Short: "查看档案列表",
		Args:  cobra.NoArgs,
		RunE: func(command *cobra.Command, _ []string) error {
			return a.runArticleList(command, page, strings.TrimSpace(category))
		},
	}
	command.Flags().IntVar(&page, "page", 1, "页码, 从 1 开始")
	command.Flags().StringVarP(&category, "category", "c", "", "分类: "+strings.Join(api.ArticleCategories, ", "))
	return command
}

func (a *App) runArticleList(command *cobra.Command, page int, keyword string) error {
	client, err := a.clientOrErr()
	if err != nil {
		return a.fail(command, err, "")
	}
	result, err := client.ArticleList(command.Context(), page, keyword)
	if err != nil {
		return a.fail(command, err, "获取档案列表")
	}
	title := "档案"
	if keyword != "" {
		title = "档案 - " + keyword
	}
	return a.finish(command, result, func(mode output.Mode) {
		a.Out.Line(mode, "共 %d 条, 第 %d 页", result.Total, result.Page)
		rows := make([][]string, 0, len(result.Items))
		for _, item := range result.Items {
			rows = append(rows, []string{item.HID, item.Title, item.Category, item.Info})
		}
		a.Out.RenderTable(mode, title, []string{"编号", "标题", "分类", "播放与时间"}, rows)
		if result.HasMore {
			a.Out.Line(mode, "还有下一页, 加 --page %d 继续", result.Page+1)
		}
	})
}

func (a *App) newArticleShowCommand() *cobra.Command {
	return &cobra.Command{
		Use:   "show 档案编号",
		Short: "查看档案详情",
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
			detail, err := client.ArticleDetail(command.Context(), hid)
			if err != nil {
				return a.fail(command, err, "获取档案详情")
			}
			return a.finish(command, detail, func(mode output.Mode) {
				a.Out.Line(mode, "%s  [%s]", detail.Title, detail.HID)
				a.Out.Line(mode, "分类: %s   发布时间: %s", detail.Category, detail.Published)
				if detail.Cover != "" {
					a.Out.Line(mode, "头图: %s", detail.Cover)
				}
				if len(detail.Tags) > 0 {
					a.Out.Line(mode, "标签: %s", strings.Join(detail.Tags, ", "))
				}
				a.Out.Line(mode, "")
				for _, block := range detail.Blocks {
					if block.Type == "image" {
						a.Out.Line(mode, "[图片] %s", block.Image)
						continue
					}
					a.Out.Line(mode, "%s", block.Text)
				}
			})
		},
	}
}

func (a *App) newArticleCommentCommand() *cobra.Command {
	var (
		page     int
		pageSize int
	)
	command := &cobra.Command{
		Use:   "comment 档案编号",
		Short: "查看档案评论",
		Long:  "档案评论的分区编号从详情页里取, 取不到时按 41 处理.",
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
			detail, err := client.ArticleDetail(command.Context(), hid)
			if err != nil {
				return a.fail(command, err, "获取档案详情")
			}
			typeID := detail.CommentTypeID
			if typeID <= 0 {
				typeID = api.ArticleCommentTypeID
			}
			thread, err := client.ReplyList(command.Context(), typeID, hid, page, pageSize, 0)
			if err != nil {
				return a.fail(command, err, "获取评论")
			}
			payload := map[string]any{
				"hid":     hid,
				"type_id": typeID,
				"thread":  thread,
			}
			return a.finish(command, payload, func(mode output.Mode) {
				a.renderReplies(mode, "档案评论", thread)
			})
		},
	}
	command.Flags().IntVar(&page, "page", 1, "页码, 从 1 开始")
	command.Flags().IntVar(&pageSize, "page-size", 20, "每页条数")
	return command
}

func (a *App) newSpaceCommand() *cobra.Command {
	var page int
	command := &cobra.Command{
		Use:   "space 用户编号",
		Short: "查看用户空间",
		Long: `查看用户的资料与投稿.

用户编号接受 442223, u442223 或 /play/u442223/ 这类写法,
编号可以从 tucao rank user 或视频详情里取.`,
		Args: cobra.ExactArgs(1),
		RunE: func(command *cobra.Command, args []string) error {
			userID, err := parseUID(args[0])
			if err != nil {
				return a.invalidInput(command, err.Error())
			}
			client, err := a.clientOrErr()
			if err != nil {
				return a.fail(command, err, "")
			}
			result, err := client.Space(command.Context(), userID, page)
			if err != nil {
				return a.fail(command, err, "获取用户空间")
			}
			return a.finish(command, result, func(mode output.Mode) {
				a.renderSpace(mode, result)
			})
		},
	}
	command.Flags().IntVar(&page, "page", 1, "页码, 从 1 开始")
	return command
}

func (a *App) renderSpace(mode output.Mode, result *model.SpaceResult) {
	if mode != output.ModeRich || result == nil {
		return
	}
	space := result.Space
	a.Out.Line(mode, "%s (%d)", space.UserName, space.UserID)
	if space.Meta != "" {
		a.Out.Line(mode, "标签: %s", space.Meta)
	}
	if space.Sign != "" {
		a.Out.Line(mode, "签名: %s", space.Sign)
	}
	if space.Total > 0 {
		a.Out.Line(mode, "投稿总数: %d", space.Total)
	}
	a.Out.RenderTable(mode, "投稿", videoHeaders, videoRows(result.Items))
	if result.HasMore {
		a.Out.Line(mode, "还有下一页, 加 --page %d 继续", result.Page+1)
	}
}
