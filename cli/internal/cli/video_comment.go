package cli

import (
	"strconv"
	"strings"

	"github.com/spf13/cobra"

	"github.com/azazo1/tucao/cli/internal/api"
	"github.com/azazo1/tucao/cli/internal/model"
	"github.com/azazo1/tucao/cli/internal/output"
)

func (a *App) newVideoCommentCommand() *cobra.Command {
	var (
		page     int
		pageSize int
		replyID  int
		typeID   int
	)
	command := &cobra.Command{
		Use:   "comment 视频编号",
		Short: "查看视频评论",
		Long: `查看视频的评论, 用 --reply-id 展开某条评论下的楼中楼回复.

档案的评论区用 tucao article comment 查看.`,
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
			resolvedTypeID, err := a.resolveTypeID(command, client, hid, typeID)
			if err != nil {
				return a.fail(command, err, "")
			}
			thread, err := client.ReplyList(command.Context(), resolvedTypeID, hid, page, pageSize, replyID)
			if err != nil {
				return a.fail(command, err, "获取评论")
			}
			return a.finish(command, thread, func(mode output.Mode) {
				a.renderReplies(mode, "评论", thread)
			})
		},
	}
	command.Flags().IntVar(&page, "page", 1, "页码, 从 1 开始")
	command.Flags().IntVar(&pageSize, "page-size", 20, "每页条数")
	command.Flags().IntVar(&replyID, "reply-id", 0, "展开指定评论下的回复")
	command.Flags().IntVar(&typeID, "type-id", 0, "视频分区编号, 留空时自动查询详情")
	command.AddCommand(a.newCommentSendCommand(), a.newCommentLikeCommand())
	return command
}

// renderReplies 输出评论树.
func (a *App) renderReplies(mode output.Mode, title string, thread *model.ReplyThread) {
	if mode != output.ModeRich || thread == nil {
		return
	}
	a.Out.Line(mode, "%s: 共 %d 条, 本页 %d 条", title, thread.Total, len(thread.Items))
	rows := make([][]string, 0, len(thread.Items))
	for _, reply := range thread.Items {
		rows = append(rows, replyRow(reply, ""))
		for _, child := range reply.Replies {
			rows = append(rows, replyRow(child, "  └ "))
		}
	}
	a.Out.RenderTable(mode, "", []string{"编号", "用户", "内容", "点赞", "回复", "时间"}, rows)
}

func replyRow(reply model.Reply, prefix string) []string {
	content := cleanInline(reply.Content)
	if reply.ReplyUserName != "" {
		content = "回复 " + reply.ReplyUserName + ": " + content
	}
	return []string{
		reply.ID,
		reply.UserName,
		prefix + content,
		strconv.Itoa(reply.Support),
		strconv.Itoa(reply.ReplyCount),
		reply.CreateAt,
	}
}

// cleanInline 把多行内容压成一行, 便于表格显示.
func cleanInline(text string) string {
	return strings.Join(strings.Fields(text), " ")
}

func (a *App) newCommentSendCommand() *cobra.Command {
	var (
		text     string
		fromFile string
		replyID  int
		replyUID int
		typeID   int
	)
	command := &cobra.Command{
		Use:   "send 视频编号 [内容]",
		Short: "发送评论或回复",
		Long: `发送评论, 需要登录.

回复某人时同时给 --reply-id 与 --reply-uid, 两者必须成对出现,
否则站点会拒收.`,
		Args: cobra.RangeArgs(1, 2),
		RunE: func(command *cobra.Command, args []string) error {
			hid, err := parseHID(args[0])
			if err != nil {
				return a.invalidInput(command, err.Error())
			}
			content, err := readContent(text, fromFile, args, 1)
			if err != nil {
				return a.invalidInput(command, err.Error())
			}
			if (replyID == 0) != (replyUID == 0) {
				return a.invalidInput(command, "--reply-id 与 --reply-uid 需要成对出现")
			}
			if err := a.requireLoginWrite("发送评论"); err != nil {
				return a.fail(command, err, "")
			}
			client, err := a.clientOrErr()
			if err != nil {
				return a.fail(command, err, "")
			}
			resolvedTypeID, err := a.resolveTypeID(command, client, hid, typeID)
			if err != nil {
				return a.fail(command, err, "")
			}
			raw, err := client.ReplySend(command.Context(), resolvedTypeID, hid, content, replyID, replyUID)
			if err != nil {
				return a.fail(command, err, "发送评论")
			}
			if message, failed := sendFailure(raw, "评论"); failed {
				return a.fail(command, api.NewError(api.CodeUpstream, "发送评论", message), "")
			}
			return a.finish(command, map[string]any{
				"hid":       hid,
				"reply_id":  replyID,
				"reply_uid": replyUID,
				"content":   content,
				"accepted":  true,
			}, func(mode output.Mode) {
				a.Out.Line(mode, "评论已发送: %s", content)
			})
		},
	}
	command.Flags().StringVar(&text, "text", "", "评论内容")
	command.Flags().StringVar(&fromFile, "from-file", "", "从文件读取评论内容")
	command.Flags().IntVar(&replyID, "reply-id", 0, "被回复的评论编号")
	command.Flags().IntVar(&replyUID, "reply-uid", 0, "被回复者的用户编号")
	command.Flags().IntVar(&typeID, "type-id", 0, "视频分区编号, 留空时自动查询详情")
	return command
}

func (a *App) newCommentLikeCommand() *cobra.Command {
	var (
		replyID string
		typeID  int
	)
	command := &cobra.Command{
		Use:   "like 视频编号",
		Short: "给评论点赞",
		Args:  cobra.ExactArgs(1),
		RunE: func(command *cobra.Command, args []string) error {
			hid, err := parseHID(args[0])
			if err != nil {
				return a.invalidInput(command, err.Error())
			}
			if strings.TrimSpace(replyID) == "" {
				return a.invalidInput(command, "缺少 --id, 评论编号可以从 tucao video comment 里取")
			}
			if err := a.requireLoginWrite("评论点赞"); err != nil {
				return a.fail(command, err, "")
			}
			client, err := a.clientOrErr()
			if err != nil {
				return a.fail(command, err, "")
			}
			resolvedTypeID, err := a.resolveTypeID(command, client, hid, typeID)
			if err != nil {
				return a.fail(command, err, "")
			}
			raw, err := client.ReplySupport(command.Context(), api.CommentID(resolvedTypeID, hid), replyID)
			if err != nil {
				return a.fail(command, err, "评论点赞")
			}
			if message, failed := sendFailure(raw, "点赞"); failed {
				return a.fail(command, api.NewError(api.CodeUpstream, "评论点赞", message), "")
			}
			return a.finish(command, map[string]any{
				"hid":      hid,
				"id":       replyID,
				"accepted": true,
			}, func(mode output.Mode) {
				a.Out.Line(mode, "已点赞评论 %s", replyID)
			})
		},
	}
	command.Flags().StringVar(&replyID, "id", "", "评论编号")
	command.Flags().IntVar(&typeID, "type-id", 0, "视频分区编号, 留空时自动查询详情")
	return command
}
