package cli

import (
	"context"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/spf13/cobra"

	"github.com/azazo1/tucao/cli/internal/api"
	"github.com/azazo1/tucao/cli/internal/download"
	"github.com/azazo1/tucao/cli/internal/imagefile"
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

图片按内容认格式: 站点上头像地址以 .jpg 结尾而内容是 PNG 的情况很常见,
所以文件名用识别出来的真实扩展名. 没有设置头像或横幅的账号会拿到占位图与
只有文件头的坏文件, 这类内容不落盘, 只在结果里作为警告列出.`,
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
					rows = append(rows, []string{
						imageLabel(item.Kind),
						item.Path,
						formatBytes(item.Bytes),
						imageSizeText(item),
						item.Source,
					})
				}
				a.Out.RenderTable(mode, "已下载", []string{"类型", "文件", "大小", "尺寸", "地址"}, rows)
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
	Format string `json:"format" yaml:"format"`
	Width  int    `json:"width" yaml:"width"`
	Height int    `json:"height" yaml:"height"`
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

// imageSizeText 把像素尺寸写成 宽x高, 未知时返回空串.
func imageSizeText(item imageItem) string {
	if item.Width <= 0 || item.Height <= 0 {
		return ""
	}
	return fmt.Sprintf("%dx%d", item.Width, item.Height)
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
// 地址缺失, 命中站点占位图与目标文件已存在的类型会被跳过并记为警告,
// 两类都没下成才算失败.
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
	fail := func(err error, warning string) {
		if firstErr == nil {
			firstErr = err
		}
		warnings = append(warnings, warning)
	}
	for _, target := range imageTargets(space, kinds) {
		label := imageLabel(target.kind)
		switch {
		case target.source == "":
			warnings = append(warnings, label+": 站点没有给出地址")
			continue
		case api.IsPlaceholderImage(target.source):
			warnings = append(warnings, label+": 该用户没有设置"+label)
			continue
		}
		if !overwrite {
			if existed := existingImage(directory, base, target.kind); existed != "" {
				err := api.NewError(api.CodeInvalidInput, "下载", "目标文件已存在: "+existed+", 加 --overwrite 覆盖")
				fail(err, label+": "+imageReason(err))
				continue
			}
		}
		item, err := a.downloadImage(ctx, client, target, base, directory, referer, overwrite)
		if err != nil {
			fail(err, label+": "+imageReason(err))
			continue
		}
		items = append(items, item)
	}
	if len(items) == 0 {
		code := api.CodeNotFound
		if firstErr != nil {
			code = api.CodeOf(firstErr)
		}
		// 每一类为什么没下到, 都写进消息里, 免得只剩一句概括.
		return nil, warnings, api.NewError(code, "下载", strings.Join(warnings, "; "))
	}
	return items, warnings, nil
}

// downloadImage 下载一张图片, 认出内容之后再按真实格式落到最终文件名.
//
// 先落在 .download 暂存文件上, 通过校验才改名; 认不出内容的一律删掉, 免得
// 像站点上的坏头像那样留下一个打不开的文件, 还让人以为下载成功了.
func (a *App) downloadImage(ctx context.Context, client *api.Client, target imageTarget,
	base, directory, referer string, overwrite bool) (imageItem, error) {
	label := imageLabel(target.kind)
	staging := filepath.Join(directory, base+"-"+target.kind+".download")
	result, err := download.File(ctx, client.HTTP, target.source, staging, download.Options{
		UserAgent: api.DesktopUserAgent,
		Referer:   referer,
		// 暂存文件是本次下载的中间产物, 每次都从头写.
		Overwrite: true,
		Progress:  a.progressPrinter(label),
	})
	if err != nil {
		return imageItem{}, err
	}
	info, err := imagefile.Inspect(result.Path)
	if err != nil {
		os.Remove(result.Path)
		if errors.Is(err, imagefile.ErrNotImage) {
			return imageItem{}, api.NewError(api.CodeNotFound, "下载", "站点返回的内容不是完整图片")
		}
		return imageItem{}, api.WrapError(api.CodeInternal, "下载", "检查"+label+"失败", err)
	}
	final := imageFileName(directory, base, target.kind, info.Extension)
	if err := replaceFile(result.Path, final, overwrite); err != nil {
		return imageItem{}, err
	}
	a.Logger.Info("图片下载完成", "kind", target.kind, "file", final,
		"format", info.Format, "width", info.Width, "height", info.Height, "bytes", result.Bytes)
	return imageItem{
		Kind:   target.kind,
		Source: target.source,
		Path:   final,
		Format: info.Format,
		Width:  info.Width,
		Height: info.Height,
		Bytes:  result.Bytes,
	}, nil
}

// imageFileName 拼出最终文件名: 前缀加类型与识别出来的扩展名.
func imageFileName(directory, base, kind, extension string) string {
	return filepath.Join(directory, base+"-"+kind+extension)
}

// imageReason 取错误的说明部分, 省掉动作前缀, 便于写进警告与汇总消息.
func imageReason(err error) string {
	var apiErr *api.Error
	if errors.As(err, &apiErr) && apiErr.Message != "" {
		return apiErr.Message
	}
	return err.Error()
}

// existingImage 找出同前缀同类型已经存在的图片.
//
// 最终扩展名由下载到的内容决定, 因此要逐个可能的扩展名试过去.
func existingImage(directory, base, kind string) string {
	for _, extension := range imagefile.Extensions() {
		path := imageFileName(directory, base, kind, extension)
		if _, err := os.Stat(path); err == nil {
			return path
		}
	}
	return ""
}

// replaceFile 把校验过的暂存文件挪到最终文件名.
func replaceFile(staging, final string, overwrite bool) error {
	if _, err := os.Stat(final); err == nil {
		if !overwrite {
			os.Remove(staging)
			return api.NewError(api.CodeInvalidInput, "下载", "目标文件已存在: "+final+", 加 --overwrite 覆盖")
		}
		if err := os.Remove(final); err != nil {
			os.Remove(staging)
			return api.WrapError(api.CodeInternal, "下载", "删除旧文件失败: "+final, err)
		}
	}
	if err := os.Rename(staging, final); err != nil {
		return api.WrapError(api.CodeInternal, "下载", "重命名失败: "+final, err)
	}
	return nil
}
