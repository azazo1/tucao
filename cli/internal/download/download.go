// Package download 负责把站点直链拉成本地文件.
//
// 站点只提供单文件媒体, 不支持 HLS 分段, 因此这里只做单文件下载:
// 断点续传靠 HTTP Range, 半成品写在 .part 文件里, 下载完成再改名.
package download

import (
	"context"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"

	"github.com/azazo1/tucao/cli/internal/api"
)

// Options 是一次下载的参数.
type Options struct {
	UserAgent string
	Referer   string
	// Overwrite 为真时覆盖已经存在的目标文件.
	Overwrite bool
	// Progress 会收到已写入字节与总字节数, 总字节数未知时为 -1.
	Progress func(received, total int64)
}

// Result 是一次下载的结果.
type Result struct {
	Path    string
	Bytes   int64
	Resumed bool
}

// File 把 source 下载到 target, 支持断点续传.
func File(ctx context.Context, client *http.Client, source, target string, options Options) (*Result, error) {
	parsed, err := validateSource(source)
	if err != nil {
		return nil, err
	}
	target = filepath.Clean(target)
	partial := target + ".part"

	if info, statErr := os.Stat(target); statErr == nil && info.Size() > 0 && !options.Overwrite {
		return nil, api.NewError(api.CodeInvalidInput, "下载",
			"目标文件已存在: "+target+", 加 --overwrite 覆盖")
	}
	var offset int64
	if info, statErr := os.Stat(partial); statErr == nil {
		offset = info.Size()
	}
	if options.Overwrite {
		if err := os.Remove(target); err != nil && !os.IsNotExist(err) {
			return nil, api.WrapError(api.CodeInternal, "下载", "删除旧文件失败: "+target, err)
		}
		if err := os.Remove(partial); err != nil && !os.IsNotExist(err) {
			return nil, api.WrapError(api.CodeInternal, "下载", "删除旧的分片失败: "+partial, err)
		}
		offset = 0
	}
	if err := os.MkdirAll(filepath.Dir(target), 0o755); err != nil {
		return nil, api.WrapError(api.CodeInternal, "下载", "创建目录失败: "+filepath.Dir(target), err)
	}

	request, err := http.NewRequestWithContext(ctx, http.MethodGet, parsed, nil)
	if err != nil {
		return nil, api.WrapError(api.CodeInvalidInput, "下载", "地址非法: "+source, err)
	}
	if options.UserAgent != "" {
		request.Header.Set("user-agent", options.UserAgent)
	}
	if options.Referer != "" {
		request.Header.Set("referer", options.Referer)
	}
	if offset > 0 {
		request.Header.Set("range", fmt.Sprintf("bytes=%d-", offset))
	}

	response, err := client.Do(request)
	if err != nil {
		return nil, api.NetworkError("下载", err)
	}
	defer response.Body.Close()

	resumed := false
	switch response.StatusCode {
	case http.StatusPartialContent:
		resumed = offset > 0
	case http.StatusOK:
		// 服务器不支持 Range, 从头写.
		offset = 0
	case http.StatusRequestedRangeNotSatisfiable:
		// 本地分片已经比服务器文件还大, 丢掉重来.
		if err := os.Remove(partial); err != nil && !os.IsNotExist(err) {
			return nil, api.WrapError(api.CodeInternal, "下载", "删除异常分片失败: "+partial, err)
		}
		return nil, api.NewError(api.CodeUpstream, "下载", "本地分片与站点文件不一致, 已清理, 请重试")
	default:
		return nil, api.NewError(api.CodeUpstream, "下载",
			fmt.Sprintf("站点返回状态码 %d", response.StatusCode))
	}
	if contentType := strings.ToLower(response.Header.Get("content-type")); strings.Contains(contentType, "text/html") {
		return nil, api.NewError(api.CodeUpstream, "下载",
			"站点返回的是网页而不是媒体, 该分P的直链可能已失效")
	}

	flags := os.O_CREATE | os.O_WRONLY
	if offset == 0 {
		flags |= os.O_TRUNC
	}
	file, err := os.OpenFile(partial, flags, 0o644)
	if err != nil {
		return nil, api.WrapError(api.CodeInternal, "下载", "打开文件失败: "+partial, err)
	}
	if offset > 0 {
		if _, err := file.Seek(offset, io.SeekStart); err != nil {
			file.Close()
			return nil, api.WrapError(api.CodeInternal, "下载", "定位分片失败: "+partial, err)
		}
	}

	total := int64(-1)
	if response.ContentLength > 0 {
		total = response.ContentLength + offset
	}
	written, copyErr := io.Copy(file, &progressReader{
		reader: response.Body,
		total:  total,
		offset: offset,
		notify: options.Progress,
	})
	if syncErr := file.Sync(); copyErr == nil {
		copyErr = syncErr
	}
	if closeErr := file.Close(); copyErr == nil {
		copyErr = closeErr
	}
	if copyErr != nil {
		return nil, api.WrapError(api.CodeNetwork, "下载", "写入文件中断: "+partial, copyErr)
	}
	if err := os.Rename(partial, target); err != nil {
		return nil, api.WrapError(api.CodeInternal, "下载", "重命名失败: "+target, err)
	}
	return &Result{Path: target, Bytes: written + offset, Resumed: resumed}, nil
}

// validateSource 校验直链, 拒绝分段媒体与非 http 地址.
func validateSource(source string) (string, error) {
	text := strings.TrimSpace(source)
	if text == "" {
		return "", api.NewError(api.CodeInvalidInput, "下载", "该分P没有可下载的直链")
	}
	if !strings.HasPrefix(text, "http://") && !strings.HasPrefix(text, "https://") {
		return "", api.NewError(api.CodeInvalidInput, "下载", "直链必须以 http 或 https 开头")
	}
	if strings.Contains(strings.ToLower(text), ".m3u8") {
		return "", api.NewError(api.CodeInvalidInput, "下载", "暂不支持分段媒体缓存")
	}
	return text, nil
}

// progressReader 上报下载进度.
type progressReader struct {
	reader  io.Reader
	total   int64
	offset  int64
	written int64
	notify  func(received, total int64)
}

func (r *progressReader) Read(buffer []byte) (int, error) {
	count, err := r.reader.Read(buffer)
	if count > 0 {
		r.written += int64(count)
		if r.notify != nil {
			r.notify(r.offset+r.written, r.total)
		}
	}
	return count, err
}
