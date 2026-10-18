package cli

import (
	"strings"

	"github.com/spf13/cobra"

	"github.com/azazo1/tucao/cli/internal/api"
	"github.com/azazo1/tucao/cli/internal/model"
	"github.com/azazo1/tucao/cli/internal/output"
)

func (a *App) newMessageCommand() *cobra.Command {
	command := &cobra.Command{
		Use:   "msg",
		Short: "查看与发送私信",
		Long: `私信需要登录.

不带子命令时列出收件箱; show 查看会话内容, send 发送新私信, reply 回复已有会话.
send 与 reply 的收件人是用户编号, 可以从 tucao rank user 或会话内容里取.`,
		Args: cobra.NoArgs,
		RunE: func(command *cobra.Command, _ []string) error {
			if err := a.requireLogin("查看私信"); err != nil {
				return a.fail(command, err, "")
			}
			client, err := a.clientOrErr()
			if err != nil {
				return a.fail(command, err, "")
			}
			items, err := client.MessageInbox(command.Context())
			if err != nil {
				return a.fail(command, err, "获取收件箱")
			}
			return a.finish(command, map[string]any{"items": items}, func(mode output.Mode) {
				a.Out.Line(mode, "共 %d 条会话", len(items))
				a.Out.RenderTable(mode, "收件箱", []string{"编号", "对方", "时间", "摘要"}, messageRows(items))
			})
		},
	}
	command.AddCommand(a.newMessageShowCommand(), a.newMessageSendCommand(), a.newMessageReplyCommand())
	return command
}

func messageRows(items []model.Message) [][]string {
	rows := make([][]string, 0, len(items))
	for _, item := range items {
		rows = append(rows, []string{item.ID, item.UserName, item.Time, cleanInline(item.Summary)})
	}
	return rows
}

// selfUID 取当前登录用户的编号, 未登录时返回空串.
func (a *App) selfUID() string {
	authStore, err := a.authOrErr()
	if err != nil || authStore.User() == nil {
		return ""
	}
	return itoaPlain(authStore.User().UserID)
}

func (a *App) newMessageShowCommand() *cobra.Command {
	return &cobra.Command{
		Use:   "show 消息编号",
		Short: "查看私信会话",
		Args:  cobra.ExactArgs(1),
		RunE: func(command *cobra.Command, args []string) error {
			if err := a.requireLogin("查看私信"); err != nil {
				return a.fail(command, err, "")
			}
			client, err := a.clientOrErr()
			if err != nil {
				return a.fail(command, err, "")
			}
			items, err := client.MessageDetail(command.Context(), strings.TrimSpace(args[0]), a.selfUID())
			if err != nil {
				return a.fail(command, err, "获取私信内容")
			}
			payload := map[string]any{"id": args[0], "items": items}
			return a.finish(command, payload, func(mode output.Mode) {
				if len(items) == 0 {
					a.Out.Line(mode, "会话里没有消息")
					return
				}
				for _, item := range items {
					who := "对方"
					if item.IsMine {
						who = "我"
					}
					a.Out.Line(mode, "[%s] %s (%s)", who, item.Content, item.Time)
				}
			})
		},
	}
}

func (a *App) newMessageSendCommand() *cobra.Command {
	var (
		to       string
		subject  string
		text     string
		fromFile string
	)
	command := &cobra.Command{
		Use:   "send [内容]",
		Short: "发送私信",
		Args:  cobra.MaximumNArgs(1),
		RunE: func(command *cobra.Command, args []string) error {
			if strings.TrimSpace(to) == "" {
				return a.invalidInput(command, "缺少 --to, 收件人用用户编号")
			}
			content, err := readContent(text, fromFile, args, 0)
			if err != nil {
				return a.invalidInput(command, err.Error())
			}
			if err := a.requireLoginWrite("发送私信"); err != nil {
				return a.fail(command, err, "")
			}
			client, err := a.clientOrErr()
			if err != nil {
				return a.fail(command, err, "")
			}
			message, err := client.MessageSend(command.Context(), strings.TrimSpace(to), subject, content)
			if err != nil {
				return a.fail(command, err, "发送私信")
			}
			if message != "" {
				return a.fail(command, api.NewError(api.CodeUpstream, "发送私信", message), "")
			}
			return a.finish(command, map[string]any{
				"to":       to,
				"subject":  subject,
				"content":  content,
				"accepted": true,
			}, func(mode output.Mode) {
				a.Out.Line(mode, "私信已发送给 %s", to)
			})
		},
	}
	command.Flags().StringVar(&to, "to", "", "收件人用户编号")
	command.Flags().StringVar(&subject, "subject", "你好", "私信标题")
	command.Flags().StringVar(&text, "text", "", "私信内容")
	command.Flags().StringVar(&fromFile, "from-file", "", "从文件读取私信内容")
	return command
}

func (a *App) newMessageReplyCommand() *cobra.Command {
	var (
		replyID  string
		to       string
		subject  string
		text     string
		fromFile string
	)
	command := &cobra.Command{
		Use:   "reply [内容]",
		Short: "回复私信会话",
		Long: `回复一条已有的私信会话.

--id 是会话编号 (收件箱里的编号), --to 是对方的用户编号.`,
		Args: cobra.MaximumNArgs(1),
		RunE: func(command *cobra.Command, args []string) error {
			if strings.TrimSpace(replyID) == "" {
				return a.invalidInput(command, "缺少 --id, 会话编号可以从 tucao msg 里取")
			}
			if strings.TrimSpace(to) == "" {
				return a.invalidInput(command, "缺少 --to, 收件人用用户编号")
			}
			content, err := readContent(text, fromFile, args, 0)
			if err != nil {
				return a.invalidInput(command, err.Error())
			}
			if err := a.requireLoginWrite("回复私信"); err != nil {
				return a.fail(command, err, "")
			}
			client, err := a.clientOrErr()
			if err != nil {
				return a.fail(command, err, "")
			}
			message, err := client.MessageReply(command.Context(), strings.TrimSpace(replyID), strings.TrimSpace(to), subject, content)
			if err != nil {
				return a.fail(command, err, "回复私信")
			}
			if message != "" {
				return a.fail(command, api.NewError(api.CodeUpstream, "回复私信", message), "")
			}
			return a.finish(command, map[string]any{
				"id":       replyID,
				"to":       to,
				"content":  content,
				"accepted": true,
			}, func(mode output.Mode) {
				a.Out.Line(mode, "已回复会话 %s", replyID)
			})
		},
	}
	command.Flags().StringVar(&replyID, "id", "", "会话编号")
	command.Flags().StringVar(&to, "to", "", "收件人用户编号")
	command.Flags().StringVar(&subject, "subject", "回复", "私信标题")
	command.Flags().StringVar(&text, "text", "", "私信内容")
	command.Flags().StringVar(&fromFile, "from-file", "", "从文件读取私信内容")
	return command
}
