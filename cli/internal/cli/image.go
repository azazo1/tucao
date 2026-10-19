package cli

import (
	"context"
	"fmt"
	"path/filepath"
	"strings"

	"github.com/spf13/cobra"

	"github.com/azazo1/tucao/cli/internal/api"
	"github.com/azazo1/tucao/cli/internal/download"
	"github.com/azazo1/tucao/cli/internal/model"
	"github.com/azazo1/tucao/cli/internal/output"
)

// 用户空间上的两类图片资源.
const (
	imageAvatar = "avatar"
	imageBanner = "banner"
)

func (a *App) newImageCommand() *cobra.Command {
	command := &cobra.Command{
		Use:   "image",
		Short: "下载用户头像与横幅",
		Long: `把站点上的图片保存到本地.

图片地址直接取自用户空间页, 下载同样支持断点续传与 --overwrite.`,
		Args: cobra.NoArgs,
	}
	command.AddCommand(a.newImageUserCommand())
	return command
}

func (a *App) newImageUserCommand() *cobra.Command {
	var (
		outputDir string
		overwrite bool
		only      string
		basename  string
	)
	command := &cobra.Command{
		Use:   "user 用户编号",
		Short: "下载用户的头像与横幅",
		Long: `下载用户空间里的头像与横幅, 默认两张都下, 用 --only 只取其中一张.

用户编号接受 442223, u442223 或 /play/u442223/ 这类写法,
编号可以从 tucao rank user 或视频详情里取.
文件名默认是 用户名-avatar 与 用户名-banner, 扩展名从图片地址里取.`,
		Args: cobra.ExactArgs(1),
		RunE: func(command *cobra.Command, args []string) error {
			userID, err := parseUID(args[0])
			if err != nil {
				return a.invalidInput(command, err.Error())
			}
			kinds, err := parseImageKinds(only)
			if err != nil {
				return a.invalidInput(command, err.Error())
			}
			client, err := a.clientOrErr()
			if err != nil {
				return a.fail(command, err, "")
			}
			space, err := client.Space(command.Context(), userID, 1)
			if err != nil {
				return a.fail(command, err, "获取用户空间")
			}
			directory, err := a.prepareDownloadDir(outputDir)
			if err != nil {
				return a.fail(command, err, "")
			}
			items, warnings, err := a.downloadImages(command.Context(), client, space.Space, kinds,
				directory, basename, overwrite || a.Config.Download.Overwrite)
			if err != nil {
				return a.fail(command, err, "下载")
			}
			payload := map[string]any{
				"user_id":   space.Space.UserID,
				"user_name": space.Space.UserName,
				"items":     items,
				"warnings":  warnings,
			}
			return a.finish(command, payload, func(mode output.Mode) {
				rows := make([][]string, 0, len(items))
				for _, item := range items {
					rows = append(rows, []string{imageLabel(item.Kind), item.Path, formatBytes(item.Bytes), item.Source})
				}
				a.Out.RenderTable(mode, "已下载", []string{"类型", "文件", "大小", "地址"}, rows)
				for _, warning := range warnings {
					a.Out.Line(mode, "警告: %s", warning)
				}
			})
		},
	}
	command.Flags().StringVarP(&outputDir, "output", "o", "", "输出目录, 默认当前目录")
	command.Flags().BoolVar(&overwrite, "overwrite", false, "覆盖已经存在的文件")
	command.Flags().StringVar(&only, "only", "", "只下载其中一种: avatar, banner")
	command.Flags().StringVar(&basename, "basename", "", "文件名前缀, 默认用用户名")
	return command
}

// imageItem 是一张图片的下载结果.
type imageItem struct {
	Kind   string `json:"kind" yaml:"kind"`
	Source string `json:"source" yaml:"source"`
	Path   string `json:"path" yaml:"path"`
	Bytes  int64  `json:"bytes" yaml:"bytes"`
}

// imageTarget 是这次要下载的一类图片.
type imageTarget struct {
	kind   string
	source string
}

// parseImageKinds 解析 --only, 空值表示两类都下载.
func parseImageKinds(only string) ([]string, error) {
	switch text := strings.ToLower(strings.TrimSpace(only)); text {
	case "":
		return []string{imageAvatar, imageBanner}, nil
	case imageAvatar, imageBanner:
		return []string{text}, nil
	default:
		return nil, fmt.Errorf("未知图片类型: %s, 可选 %s, %s", only, imageAvatar, imageBanner)
	}
}

// imageLabel 返回图片类型的中文名.
func imageLabel(kind string) string {
	switch kind {
	case imageAvatar:
		return "头像"
	case imageBanner:
		return "横幅"
	default:
		return kind
	}
}

// imageTargets 按 --only 的顺序挑出要下载的图片地址.
func imageTargets(space model.Space, kinds []string) []imageTarget {
	targets := make([]imageTarget, 0, len(kinds))
	for _, kind := range kinds {
		switch kind {
		case imageAvatar:
			targets = append(targets, imageTarget{kind: kind, source: space.Avatar})
		case imageBanner:
			targets = append(targets, imageTarget{kind: kind, source: space.Banner})
		}
	}
	return targets
}

// downloadImages 下载用户空间里的头像与横幅.
//
// 某一类地址缺失时记为警告并继续下载另一类, 两类都没下成才算失败.
func (a *App) downloadImages(ctx context.Context, client *api.Client, space model.Space, kinds []string,
	directory, basename string, overwrite bool) ([]imageItem, []string, error) {
	base := strings.TrimSpace(basename)
	if base == "" {
		base = sanitizeFileName(space.UserName)
	}
	if base == "" {
		base = "tucao-" + itoaPlain(space.UserID)
	}
	// 站点按来源页判断图片能不能取, 因此带上空间页作为 referer.
	referer := client.SiteURL(api.UserPath(space.UserID))

	items := make([]imageItem, 0, len(kinds))
	warnings := []string{}
	var firstErr error
	for _, target := range imageTargets(space, kinds) {
		label := imageLabel(target.kind)
		if target.source == "" {
			warnings = append(warnings, "站点没有返回"+label+"地址")
			continue
		}
		path := filepath.Join(directory, imageFileName(base, target.kind, target.source))
		result, err := download.File(ctx, client.HTTP, target.source, path, download.Options{
			UserAgent: api.DesktopUserAgent,
			Referer:   referer,
			Overwrite: overwrite,
			Progress:  a.progressPrinter(label),
		})
		if err != nil {
			if firstErr == nil {
				firstErr = err
			}
			warnings = append(warnings, label+"下载失败: "+err.Error())
			continue
		}
		a.Logger.Info("图片下载完成", "kind", target.kind, "file", result.Path, "bytes", result.Bytes)
		items = append(items, imageItem{
			Kind:   target.kind,
			Source: target.source,
			Path:   result.Path,
			Bytes:  result.Bytes,
		})
	}
	if len(items) == 0 {
		if firstErr != nil {
			return nil, warnings, firstErr
		}
		return nil, warnings, api.NewError(api.CodeNotFound, "下载", "该用户没有可下载的头像或横幅")
	}
	return items, warnings, nil
}

// imageFileName 决定图片文件名, 前缀后面接类型后缀.
func imageFileName(base, kind, source string) string {
	return base + "-" + kind + imageExtension(source)
}

// imageExtension 从图片地址里取扩展名, 取不到时按 .jpg 处理.
//
// 站点把图片挂在 uploadfile 目录下, 扩展名一般是 .jpg, 但也可能出现 .png 与 .gif,
// 因此只认常见的图片扩展名.
func imageExtension(source string) string {
	path := source
	if index := strings.IndexAny(path, "?#"); index >= 0 {
		path = path[:index]
	}
	extension := strings.ToLower(filepath.Ext(path))
	if !imageExtensions[extension] {
		return ".jpg"
	}
	return extension
}

// imageExtensions 是可识别的图片扩展名.
var imageExtensions = map[string]bool{
	".jpg":  true,
	".jpeg": true,
	".png":  true,
	".gif":  true,
	".webp": true,
	".bmp":  true,
	".avif": true,
}
