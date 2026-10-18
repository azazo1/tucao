package cli

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"
	"unicode/utf8"

	"github.com/spf13/cobra"

	"github.com/azazo1/tucao/cli/internal/api"
	"github.com/azazo1/tucao/cli/internal/danmaku"
	"github.com/azazo1/tucao/cli/internal/download"
	"github.com/azazo1/tucao/cli/internal/model"
	"github.com/azazo1/tucao/cli/internal/output"
)

func (a *App) newVideoDownloadCommand() *cobra.Command {
	var (
		part        int
		allParts    bool
		outputDir   string
		overwrite   bool
		threads     int
		withDanmaku bool
		basename    string
	)
	command := &cobra.Command{
		Use:   "download 视频编号",
		Short: "下载分P到本地",
		Long: `把分P的直链下载到本地, 默认落在当前目录, 用 -o 指定其它目录.

站点只提供单文件媒体, 不支持 HLS 分段缓存. 下载中断时会留下 .part 文件,
再次执行同一命令会从断点续传; 目标文件已存在时需要用 --overwrite 覆盖.

多分P视频必须用 --part 指定分P, 或用 --all-parts 全部下载.`,
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
			selected, err := selectParts(video, part, allParts)
			if err != nil {
				return a.fail(command, err, "")
			}
			directory := strings.TrimSpace(outputDir)
			if directory == "" {
				directory = a.Config.Download.OutputDir
			}
			if directory == "" {
				directory = "."
			}
			if err := os.MkdirAll(directory, 0o755); err != nil {
				return a.fail(command, api.WrapError(api.CodeInternal, "下载", "创建目录失败: "+directory, err), "")
			}
			concurrency := threads
			if concurrency <= 0 {
				concurrency = a.Config.Download.Threads
			}
			items, warnings, err := a.downloadParts(command.Context(), client, video, selected, directory, basename, concurrency, overwrite || a.Config.Download.Overwrite)
			if err != nil {
				return a.fail(command, err, "下载")
			}
			if withDanmaku && len(items) > 0 {
				if warning := a.downloadDanmaku(command.Context(), client, video, selected, directory, basename); warning != "" {
					warnings = append(warnings, warning)
				}
			}
			payload := map[string]any{"hid": hid, "items": items, "warnings": warnings}
			return a.finish(command, payload, func(mode output.Mode) {
				rows := make([][]string, 0, len(items))
				for _, item := range items {
					rows = append(rows, []string{
						itoaPlain(item.Part),
						item.Title,
						item.Path,
						formatBytes(item.Bytes),
					})
				}
				a.Out.RenderTable(mode, "已下载", []string{"分P", "标题", "文件", "大小"}, rows)
				for _, warning := range warnings {
					a.Out.Line(mode, "警告: %s", warning)
				}
			})
		},
	}
	command.Flags().IntVar(&part, "part", 0, "分P序号, 从 1 开始")
	command.Flags().BoolVar(&allParts, "all-parts", false, "下载全部分P")
	command.Flags().StringVarP(&outputDir, "output", "o", "", "输出目录, 默认当前目录")
	command.Flags().BoolVar(&overwrite, "overwrite", false, "覆盖已经存在的文件")
	command.Flags().IntVar(&threads, "threads", 0, "多分P下载并发数, 默认取配置")
	command.Flags().BoolVar(&withDanmaku, "with-danmaku", false, "顺带导出同名 ass 弹幕")
	command.Flags().StringVar(&basename, "basename", "", "文件名前缀, 默认用视频标题")
	return command
}

// downloadItem 是一个分P的下载结果.
type downloadItem struct {
	Part    int    `json:"part" yaml:"part"`
	Title   string `json:"title" yaml:"title"`
	Path    string `json:"path" yaml:"path"`
	Bytes   int64  `json:"bytes" yaml:"bytes"`
	Resumed bool   `json:"resumed" yaml:"resumed"`
}

// selectParts 决定要下载哪些分P.
func selectParts(video *model.Video, part int, allParts bool) ([]model.VideoPart, error) {
	if len(video.Parts) == 0 {
		return nil, api.NewError(api.CodeNotFound, "下载", "站点没有返回可用分P")
	}
	if allParts {
		return video.Parts, nil
	}
	if part > 0 {
		if part > len(video.Parts) {
			return nil, api.NewError(api.CodeInvalidInput, "下载",
				fmt.Sprintf("视频只有 %d 个分P", len(video.Parts)))
		}
		return video.Parts[part-1 : part], nil
	}
	if len(video.Parts) == 1 {
		return video.Parts, nil
	}
	names := make([]string, 0, len(video.Parts))
	for _, item := range video.Parts {
		names = append(names, fmt.Sprintf("%d. %s", item.Number, item.Title))
	}
	return nil, api.NewError(api.CodeInvalidInput, "下载",
		"该视频有多个分P, 请用 --part 指定或用 --all-parts: "+strings.Join(names, " / "))
}

func (a *App) downloadParts(ctx context.Context, client *api.Client, video *model.Video, parts []model.VideoPart, directory, basename string, concurrency int, overwrite bool) ([]downloadItem, []string, error) {
	if concurrency < 1 {
		concurrency = 1
	}
	if concurrency > len(parts) {
		concurrency = len(parts)
	}
	items := make([]downloadItem, len(parts))
	warnings := []string{}
	errs := make([]error, len(parts))
	semaphore := make(chan struct{}, concurrency)
	var waitGroup sync.WaitGroup
	for index, selected := range parts {
		if strings.TrimSpace(selected.File) == "" {
			errs[index] = api.NewError(api.CodeInvalidInput, "下载",
				fmt.Sprintf("第 %d 分P的播放地址已失效, 该分P是第三方源", selected.Number))
			continue
		}
		waitGroup.Add(1)
		go func(index int, selected model.VideoPart) {
			defer waitGroup.Done()
			semaphore <- struct{}{}
			defer func() { <-semaphore }()

			target := filepath.Join(directory, a.mediaFileName(video, selected, basename))
			progress := a.progressPrinter(selected.Title)
			result, err := download.File(ctx, client.HTTP, selected.File, target, download.Options{
				UserAgent: api.MobileUserAgent,
				Referer:   client.BaseURL,
				Overwrite: overwrite,
				Progress:  progress,
			})
			if err != nil {
				errs[index] = err
				return
			}
			a.Logger.Info("下载完成", "part", selected.Number, "file", result.Path, "bytes", result.Bytes)
			items[index] = downloadItem{
				Part:    selected.Number,
				Title:   selected.Title,
				Path:    result.Path,
				Bytes:   result.Bytes,
				Resumed: result.Resumed,
			}
		}(index, selected)
	}
	waitGroup.Wait()

	result := make([]downloadItem, 0, len(items))
	for index, item := range items {
		if errs[index] != nil {
			warnings = append(warnings, fmt.Sprintf("第 %d 分P下载失败: %s", parts[index].Number, errs[index].Error()))
			continue
		}
		result = append(result, item)
	}
	if len(result) == 0 {
		if len(errs) > 0 && errs[0] != nil {
			return nil, warnings, errs[0]
		}
		return nil, warnings, api.NewError(api.CodeInternal, "下载", "没有下载任何分P")
	}
	return result, warnings, nil
}

// mediaFileName 决定下载文件的文件名.
//
// 单分P视频直接用标题, 多分P加上分P序号; 标题里的路径分隔符会被替换掉.
func (a *App) mediaFileName(video *model.Video, part model.VideoPart, basename string) string {
	base := strings.TrimSpace(basename)
	if base == "" {
		base = sanitizeFileName(video.Title)
		if base == "" {
			base = "tucao-" + video.HID
		}
		if len(video.Parts) > 1 {
			base = fmt.Sprintf("%s-p%d", base, part.Number)
		}
	}
	return base + mediaExtension(part.File)
}

// mediaExtension 从直链里取扩展名, 取不到时按 mp4 处理.
func mediaExtension(source string) string {
	path := source
	if index := strings.IndexAny(path, "?#"); index >= 0 {
		path = path[:index]
	}
	extension := filepath.Ext(path)
	if len(extension) < 2 || len(extension) > 5 {
		return ".mp4"
	}
	return strings.ToLower(extension)
}

// sanitizeFileName 去掉文件名里的路径分隔符与控制字符.
func sanitizeFileName(raw string) string {
	text := strings.Map(func(symbol rune) rune {
		switch {
		case symbol < 0x20:
			return -1
		case strings.ContainsRune(`/\:*?"<>|`, symbol):
			return '_'
		default:
			return symbol
		}
	}, strings.TrimSpace(raw))
	text = strings.Trim(text, ". ")
	const limit = 100
	if utf8.RuneCountInString(text) > limit {
		runes := []rune(text)
		text = string(runes[:limit])
	}
	return text
}

// downloadDanmaku 顺带导出与视频同名的 ass 弹幕.
func (a *App) downloadDanmaku(ctx context.Context, client *api.Client, video *model.Video, parts []model.VideoPart, directory, basename string) string {
	for _, selected := range parts {
		items, err := client.DanmakuFetch(ctx, video.TypeID, video.HID, selected.Index)
		if err != nil {
			return "弹幕导出失败: " + err.Error()
		}
		base := strings.TrimSpace(basename)
		if base == "" {
			base = sanitizeFileName(video.Title)
			if base == "" {
				base = "tucao-" + video.HID
			}
			if len(video.Parts) > 1 {
				base = fmt.Sprintf("%s-p%d", base, selected.Number)
			}
		}
		path := filepath.Join(directory, base+".ass")
		file, err := os.Create(path)
		if err != nil {
			return "弹幕导出失败: " + err.Error()
		}
		writeErr := danmaku.WriteASS(file, items, a.danmakuOptions())
		closeErr := file.Close()
		if writeErr != nil {
			return "弹幕导出失败: " + writeErr.Error()
		}
		if closeErr != nil {
			return "弹幕导出失败: " + closeErr.Error()
		}
		a.Logger.Info("已导出弹幕", "path", path, "count", len(items))
	}
	return ""
}

// progressPrinter 在交互终端画一行进度, 非交互时按阶段写日志.
func (a *App) progressPrinter(title string) func(received, total int64) {
	interactive := output.IsTerminal(a.Out.Stderr)
	var (
		lastPrint time.Time
		lastLog   time.Time
		mutex     sync.Mutex
	)
	return func(received, total int64) {
		mutex.Lock()
		defer mutex.Unlock()
		now := time.Now()
		if interactive {
			if now.Sub(lastPrint) < 100*time.Millisecond && (total <= 0 || received < total) {
				return
			}
			lastPrint = now
			fmt.Fprintf(a.Out.Stderr, "\r%s %s / %s", truncateText(title, 24),
				formatBytes(received), formatBytes(total))
			if total > 0 && received >= total {
				fmt.Fprintln(a.Out.Stderr)
			}
			return
		}
		if now.Sub(lastLog) < 5*time.Second {
			return
		}
		lastLog = now
		a.Logger.Info("下载中", "title", title, "received", received, "total", total)
	}
}

// truncateText 按显示宽度截断文本.
func truncateText(text string, limit int) string {
	runes := []rune(text)
	if len(runes) <= limit {
		return text
	}
	return string(runes[:limit]) + "..."
}

// formatBytes 把字节数转成便于阅读的单位.
func formatBytes(bytes int64) string {
	const (
		kilo = 1024
		mega = kilo * 1024
		giga = mega * 1024
	)
	switch {
	case bytes < 0:
		return "未知"
	case bytes < kilo:
		return fmt.Sprintf("%d B", bytes)
	case bytes < mega:
		return fmt.Sprintf("%.1f KB", float64(bytes)/kilo)
	case bytes < giga:
		return fmt.Sprintf("%.1f MB", float64(bytes)/mega)
	default:
		return fmt.Sprintf("%.2f GB", float64(bytes)/giga)
	}
}
