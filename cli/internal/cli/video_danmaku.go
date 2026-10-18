package cli

import (
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"

	"github.com/spf13/cobra"

	"github.com/azazo1/tucao/cli/internal/api"
	"github.com/azazo1/tucao/cli/internal/danmaku"
	"github.com/azazo1/tucao/cli/internal/model"
	"github.com/azazo1/tucao/cli/internal/output"
)

// exportFormats 是支持的导出格式.
var exportFormats = map[string]bool{"ass": true, "xml": true, "txt": true}

func (a *App) newVideoDanmakuCommand() *cobra.Command {
	var (
		part      int
		typeID    int
		formats   []string
		limit     int
		outputDir string
		basename  string
		from      string
		to        string
	)
	command := &cobra.Command{
		Use:   "danmaku 视频编号",
		Short: "拉取并导出弹幕",
		Long: `拉取某一分P的弹幕, 导出一份或多份文件.

默认只在终端预览前 20 条; 加 --format 后写出文件, 文件名默认是
<视频编号>-p<分P序号>.<扩展名>, 例如 4107860-p1.ass.
导出文件始终包含拉到的全部弹幕, 不受 --limit 影响.`,
		Args: cobra.ExactArgs(1),
		RunE: func(command *cobra.Command, args []string) error {
			hid, err := parseHID(args[0])
			if err != nil {
				return a.invalidInput(command, err.Error())
			}
			if part <= 0 {
				return a.invalidInput(command, "分P序号必须是从 1 开始的整数")
			}
			extends, err := normalizeFormats(formats)
			if err != nil {
				return a.invalidInput(command, err.Error())
			}
			window := danmaku.Filter{}
			if from != "" {
				value, err := parseTimeSpec(from)
				if err != nil {
					return a.invalidInput(command, err.Error())
				}
				window.From = value
			}
			if to != "" {
				value, err := parseTimeSpec(to)
				if err != nil {
					return a.invalidInput(command, err.Error())
				}
				window.To = value
			}
			if limit < 0 {
				return a.invalidInput(command, "--limit 不能为负数")
			}

			client, err := a.clientOrErr()
			if err != nil {
				return a.fail(command, err, "")
			}
			resolvedTypeID, err := a.resolveTypeID(command, client, hid, typeID)
			if err != nil {
				return a.fail(command, err, "")
			}
			items, err := client.DanmakuFetch(command.Context(), resolvedTypeID, hid, part-1)
			if err != nil {
				return a.fail(command, err, "获取弹幕")
			}
			items = danmaku.Apply(items, window)

			result := map[string]any{
				"hid":      hid,
				"part":     part,
				"typeid":   resolvedTypeID,
				"count":    len(items),
				"exported": []any{},
				"items":    previewDanmaku(items, limit),
			}
			if len(extends) > 0 {
				base := basename
				if base == "" {
					base = fmt.Sprintf("%s-p%d", hid, part)
				}
				exported, err := a.exportDanmaku(extends, items, outputDir, base)
				if err != nil {
					return a.fail(command, err, "导出弹幕")
				}
				result["exported"] = exported
			}
			return a.finish(command, result, func(mode output.Mode) {
				a.renderDanmaku(mode, hid, part, items, result)
			})
		},
	}
	command.Flags().IntVar(&part, "part", 1, "分P序号, 从 1 开始")
	command.Flags().IntVar(&typeID, "type-id", 0, "视频分区编号, 留空时自动查询详情")
	command.Flags().StringSliceVar(&formats, "format", nil, "导出格式: ass, xml, txt, 可重复传参")
	command.Flags().IntVar(&limit, "limit", 20, "终端预览条数, 0 表示不截断")
	command.Flags().StringVarP(&outputDir, "output", "o", "", "导出目录, 默认当前目录")
	command.Flags().StringVar(&basename, "basename", "", "导出文件名前缀, 默认 <视频编号>-p<分P序号>")
	command.Flags().StringVar(&from, "from", "", "只保留该时间之后的弹幕, 支持 90s 与 1m30s")
	command.Flags().StringVar(&to, "to", "", "只保留该时间之前的弹幕")
	command.AddCommand(a.newDanmakuSendCommand())
	return command
}

// resolveTypeID 取视频分区编号, 参数里给了就直接用, 否则查一次详情.
func (a *App) resolveTypeID(command *cobra.Command, client *api.Client, hid string, typeID int) (int, error) {
	if typeID > 0 {
		return typeID, nil
	}
	video, err := client.VideoView(command.Context(), hid)
	if err != nil {
		return 0, err
	}
	if video.TypeID <= 0 {
		return 0, api.NewError(api.CodeUpstream, "获取分区", "站点没有返回视频分区, 可用 --type-id 指定")
	}
	return video.TypeID, nil
}

func normalizeFormats(values []string) ([]string, error) {
	seen := map[string]bool{}
	result := []string{}
	for _, value := range values {
		for _, part := range strings.Split(value, ",") {
			format := strings.ToLower(strings.TrimSpace(part))
			if format == "" {
				continue
			}
			if !exportFormats[format] {
				return nil, fmt.Errorf("不支持的导出格式: %s", format)
			}
			if seen[format] {
				continue
			}
			seen[format] = true
			result = append(result, format)
		}
	}
	return result, nil
}

// exportDanmaku 把弹幕写成文件, 返回每个文件的描述.
func (a *App) exportDanmaku(formats []string, items []model.Danmaku, outputDir, base string) ([]any, error) {
	directory := strings.TrimSpace(outputDir)
	if directory == "" {
		directory = a.Config.Download.OutputDir
	}
	if directory == "" {
		directory = "."
	}
	if err := os.MkdirAll(directory, 0o755); err != nil {
		return nil, api.WrapError(api.CodeInternal, "导出弹幕", "创建目录失败: "+directory, err)
	}
	exported := make([]any, 0, len(formats))
	for _, format := range formats {
		path := filepath.Join(directory, base+"."+format)
		file, err := os.Create(path)
		if err != nil {
			return nil, api.WrapError(api.CodeInternal, "导出弹幕", "创建文件失败: "+path, err)
		}
		writeErr := error(nil)
		switch format {
		case "ass":
			writeErr = danmaku.WriteASS(file, items, a.danmakuOptions())
		case "xml":
			writeErr = danmaku.WriteXML(file, items)
		case "txt":
			writeErr = danmaku.WriteText(file, items)
		}
		closeErr := file.Close()
		if writeErr != nil {
			return nil, api.WrapError(api.CodeInternal, "导出弹幕", "写入文件失败: "+path, writeErr)
		}
		if closeErr != nil {
			return nil, api.WrapError(api.CodeInternal, "导出弹幕", "关闭文件失败: "+path, closeErr)
		}
		info, err := os.Stat(path)
		size := int64(0)
		if err == nil {
			size = info.Size()
		}
		exported = append(exported, map[string]any{
			"format": format,
			"path":   path,
			"bytes":  size,
		})
		a.Logger.Info("已导出弹幕", "format", format, "path", path, "count", len(items))
	}
	return exported, nil
}

// danmakuOptions 取配置里的 ass 排版参数.
func (a *App) danmakuOptions() danmaku.Options {
	return danmaku.Options{
		Font:                  a.Config.Danmaku.Font,
		FontSize:              a.Config.Danmaku.FontSize,
		DurationSeconds:       a.Config.Danmaku.DurationSeconds,
		StaticDurationSeconds: a.Config.Danmaku.StaticDurationSeconds,
		Area:                  a.Config.Danmaku.Area,
		Opacity:               a.Config.Danmaku.Opacity,
		StrokeWidth:           a.Config.Danmaku.StrokeWidth,
		LineHeight:            a.Config.Danmaku.LineHeight,
		HideScroll:            a.Config.Danmaku.HideScroll,
		HideTop:               a.Config.Danmaku.HideTop,
		HideBottom:            a.Config.Danmaku.HideBottom,
	}
}

func previewDanmaku(items []model.Danmaku, limit int) []model.Danmaku {
	if limit <= 0 || len(items) <= limit {
		return items
	}
	return items[:limit]
}

func (a *App) renderDanmaku(mode output.Mode, hid string, part int, items []model.Danmaku, result map[string]any) {
	if mode != output.ModeRich {
		return
	}
	a.Out.Line(mode, "视频 %s 第 %d 分P, 共 %d 条弹幕", hid, part, len(items))
	if exported, ok := result["exported"].([]any); ok && len(exported) > 0 {
		for _, entry := range exported {
			item, _ := entry.(map[string]any)
			a.Out.Line(mode, "已导出 %v: %v", item["format"], item["path"])
		}
	}
	preview, _ := result["items"].([]model.Danmaku)
	if len(preview) == 0 {
		return
	}
	rows := make([][]string, 0, len(preview))
	for _, item := range preview {
		rows = append(rows, []string{
			formatDuration(item.Time),
			item.Position,
			strconv.Itoa(item.FontSize),
			fmt.Sprintf("#%06X", item.Color),
			item.Text,
		})
	}
	title := fmt.Sprintf("弹幕预览 (%d 条)", len(preview))
	if len(preview) < len(items) {
		title = fmt.Sprintf("弹幕预览 (%d / %d 条)", len(preview), len(items))
	}
	a.Out.RenderTable(mode, title, []string{"时间", "位置", "字号", "颜色", "内容"}, rows)
}

func (a *App) newDanmakuSendCommand() *cobra.Command {
	var (
		text     string
		fromFile string
		progress string
		part     int
		typeID   int
		modeName string
		color    string
		fontSize int
	)
	command := &cobra.Command{
		Use:   "send 视频编号 [内容]",
		Short: "发送弹幕",
		Long: `发送一条弹幕, 需要登录.

--progress 是弹幕出现的时间, 支持 12.5, 12.5s, 1m20s, 1:20 与 1:20:00.
--mode 支持 scroll, top 与 bottom, --color 支持 #RRGGBB 或十进制 rgb.`,
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
			if progress == "" {
				return a.invalidInput(command, "缺少 --progress, 例如 --progress 1m20s")
			}
			at, err := parseTimeSpec(progress)
			if err != nil {
				return a.invalidInput(command, err.Error())
			}
			danmakuMode, err := parseDanmakuMode(modeName)
			if err != nil {
				return a.invalidInput(command, err.Error())
			}
			rgb, err := parseColor(color)
			if err != nil {
				return a.invalidInput(command, err.Error())
			}
			if err := a.requireLoginWrite("发送弹幕"); err != nil {
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
			raw, err := client.DanmakuSend(command.Context(), resolvedTypeID, hid, part-1, content, at, rgb, danmakuMode, fontSize)
			if err != nil {
				return a.fail(command, err, "发送弹幕")
			}
			if message, failed := sendFailure(raw, "弹幕"); failed {
				return a.fail(command, api.NewError(api.CodeUpstream, "发送弹幕", message), "")
			}
			return a.finish(command, map[string]any{
				"hid":      hid,
				"part":     part,
				"time":     at,
				"mode":     modeName,
				"color":    fmt.Sprintf("#%06X", rgb),
				"text":     content,
				"accepted": true,
			}, func(mode output.Mode) {
				a.Out.Line(mode, "弹幕已发送: %s", content)
			})
		},
	}
	command.Flags().StringVar(&text, "text", "", "弹幕内容")
	command.Flags().StringVar(&fromFile, "from-file", "", "从文件读取弹幕内容")
	command.Flags().StringVar(&progress, "progress", "", "弹幕出现时间, 例如 12.5, 1m20s 或 1:20")
	command.Flags().IntVar(&part, "part", 1, "分P序号, 从 1 开始")
	command.Flags().IntVar(&typeID, "type-id", 0, "视频分区编号, 留空时自动查询详情")
	command.Flags().StringVar(&modeName, "mode", "scroll", "位置: scroll, top, bottom")
	command.Flags().StringVar(&color, "color", "#FFFFFF", "颜色, #RRGGBB 或十进制 rgb")
	command.Flags().IntVar(&fontSize, "size", 25, "字号")
	return command
}

// parseDanmakuMode 把位置名转成站点弹幕类型.
func parseDanmakuMode(raw string) (int, error) {
	switch strings.ToLower(strings.TrimSpace(raw)) {
	case "scroll", "1", "滚动":
		return 1, nil
	case "top", "5", "顶部":
		return 5, nil
	case "bottom", "4", "底部":
		return 4, nil
	default:
		return 0, fmt.Errorf("弹幕位置只支持 scroll, top 与 bottom")
	}
}

// parseColor 解析颜色, 支持 #RRGGBB 与十进制 rgb.
func parseColor(raw string) (int, error) {
	text := strings.TrimSpace(raw)
	if text == "" {
		return 0xFFFFFF, nil
	}
	if strings.HasPrefix(text, "#") {
		value, err := strconv.ParseInt(strings.TrimPrefix(text, "#"), 16, 32)
		if err != nil || value < 0 || value > 0xFFFFFF {
			return 0, fmt.Errorf("颜色需要是 #RRGGBB 形式, 例如 #FF0000")
		}
		return int(value), nil
	}
	value, err := strconv.Atoi(text)
	if err != nil || value < 0 || value > 0xFFFFFF {
		return 0, fmt.Errorf("颜色需要是 #RRGGBB 或 0 到 16777215 的十进制值")
	}
	return value, nil
}

// readContent 从参数, --text 或 --from-file 取内容.
func readContent(text, fromFile string, args []string, positional int) (string, error) {
	content := strings.TrimSpace(text)
	if content == "" && len(args) > positional {
		content = strings.TrimSpace(args[positional])
	}
	if content == "" && fromFile != "" {
		data, err := os.ReadFile(fromFile)
		if err != nil {
			return "", fmt.Errorf("读取内容文件失败: %v", err)
		}
		content = strings.TrimSpace(string(data))
	}
	if content == "" {
		return "", fmt.Errorf("内容不能为空")
	}
	return content, nil
}

// sendFailure 解析站点返回的写操作结果, 成功返回空.
func sendFailure(raw, what string) (string, bool) {
	text := strings.TrimSpace(stripTags(raw))
	if text == "" || text == "1" || strings.Contains(text, "成功") {
		return "", false
	}
	if strings.Contains(text, "登录") || strings.Contains(text, "登陆") {
		return "请先登录后再操作", true
	}
	if len(text) > 40 {
		return what + "发送失败", true
	}
	return text, true
}

// stripTags 去掉 html 标签, 站点偶尔用标签包裹提示文本.
func stripTags(raw string) string {
	var builder strings.Builder
	inTag := false
	for _, symbol := range raw {
		switch {
		case symbol == '<':
			inTag = true
		case symbol == '>':
			inTag = false
		case !inTag:
			builder.WriteRune(symbol)
		}
	}
	return builder.String()
}
