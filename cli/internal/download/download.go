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
	// Retries 是传输中断后的续传次数, 0 表示使用默认值.
	Retries int
}

// DefaultRetries 是传输中断后的默认续传次数.
const DefaultRetries = 5

// Result 是一次下载的结果.
type Result struct {
	Path    string
	Bytes   int64
	Resumed bool
	// Retried 是中途续传的次数.
	Retried int
}

// File 把 source 下载到 target, 支持断点续传.
//
// 大文件经常传到一半被对端掐断, 这种情况不是失败而是可以接着传,
// 因此中断后会带着现有分片重试, 次数用完才报错.
func File(ctx context.Context, client *http.Client, source, target string, options Options) (*Result, error) {
	if _, err := validateSource(source); err != nil {
		return nil, err
	}
	target = filepath.Clean(target)
	partial := target + ".part"

	if info, statErr := os.Stat(target); statErr == nil && info.Size() > 0 && !options.Overwrite {
		return nil, api.NewError(api.CodeInvalidInput, "下载",
			"目标文件已存在: "+target+", 加 --overwrite 覆盖")
	}
	if options.Overwrite {
		if err := os.Remove(target); err != nil && !os.IsNotExist(err) {
			return nil, api.WrapError(api.CodeInternal, "下载", "删除旧文件失败: "+target, err)
		}
		if err := os.Remove(partial); err != nil && !os.IsNotExist(err) {
			return nil, api.WrapError(api.CodeInternal, "下载", "删除旧的分片失败: "+partial, err)
		}
	}
	if err := os.MkdirAll(filepath.Dir(target), 0o755); err != nil {
		return nil, api.WrapError(api.CodeInternal, "下载", "创建目录失败: "+filepath.Dir(target), err)
	}

	retries := options.Retries
	if retries <= 0 {
		retries = DefaultRetries
	}
	result := &Result{Path: target}
	for attempt := 0; ; attempt++ {
		// 每轮都重新读分片大小, 断流留下的字节就是本轮的起点.
		offset := partialSize(partial)
		written, start, err := downloadOnce(ctx, client, source, partial, offset, options)
		if start > 0 {
			// 只有真的从分片末尾接着写才算续传.
			result.Resumed = true
		}
		if err == nil {
			result.Bytes = start + written
			if err := os.Rename(partial, target); err != nil {
				return nil, api.WrapError(api.CodeInternal, "下载", "重命名失败: "+target, err)
			}
			return result, nil
		}
		if !retryable(err) || attempt >= retries {
			if attempt > 0 {
				err = api.WrapError(api.CodeOf(err), "下载",
					fmt.Sprintf("重试 %d 次后仍未完成, 已下载的部分保留在 %s, 再次执行可续传", attempt, partial), err)
			}
			return nil, err
		}
		result.Retried++
	}
}

// partialSize 返回分片已有字节数, 不存在时为 0.
func partialSize(partial string) int64 {
	info, err := os.Stat(partial)
	if err != nil {
		return 0
	}
	return info.Size()
}

// retryable 判断这类错误是否值得续传重试.
//
// 传输中断与网络错误可以接着传; 直链失效, 参数错误这类重试也没用.
func retryable(err error) bool {
	switch api.CodeOf(err) {
	case api.CodeNetwork, api.CodeUpstream, api.CodeInternal:
		return true
	default:
		return false
	}
}

// downloadOnce 从 offset 处拉一次, 返回本次写入的字节数与真正使用的起点.
//
// 服务器不支持 Range 时会从头写, 此时返回的起点是 0, 调用方据此判断是否算续传.
func downloadOnce(ctx context.Context, client *http.Client, source, partial string, offset int64, options Options) (written int64, start int64, err error) {
	if err := ctx.Err(); err != nil {
		return 0, offset, api.WrapError(api.CodeNetwork, "下载", "下载已取消", err)
	}
	request, err := http.NewRequestWithContext(ctx, http.MethodGet, source, nil)
	if err != nil {
		return 0, offset, api.WrapError(api.CodeInvalidInput, "下载", "地址非法: "+source, err)
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
		return 0, offset, api.NetworkError("下载", err)
	}
	defer response.Body.Close()

	switch response.StatusCode {
	case http.StatusPartialContent:
		// 本次接着分片往后写.
	case http.StatusOK:
		// 服务器不支持 Range, 从头写.
		offset = 0
	case http.StatusRequestedRangeNotSatisfiable:
		if err := os.Remove(partial); err != nil && !os.IsNotExist(err) {
			return 0, offset, api.WrapError(api.CodeInternal, "下载", "删除异常分片失败: "+partial, err)
		}
		return 0, offset, api.NewError(api.CodeUpstream, "下载", "本地分片与站点文件不一致, 已清理, 请重试")
	default:
		return 0, offset, api.NewError(api.CodeUpstream, "下载",
			fmt.Sprintf("站点返回状态码 %d", response.StatusCode))
	}
	if contentType := strings.ToLower(response.Header.Get("content-type")); strings.Contains(contentType, "text/html") {
		return 0, offset, api.NewError(api.CodeUpstream, "下载",
			"站点返回的是网页而不是媒体, 该分P的直链可能已失效")
	}

	flags := os.O_CREATE | os.O_WRONLY
	if offset == 0 {
		flags |= os.O_TRUNC
	}
	file, err := os.OpenFile(partial, flags, 0o644)
	if err != nil {
		return 0, offset, api.WrapError(api.CodeInternal, "下载", "打开文件失败: "+partial, err)
	}
	if offset > 0 {
		if _, err := file.Seek(offset, io.SeekStart); err != nil {
			file.Close()
			return 0, offset, api.WrapError(api.CodeInternal, "下载", "定位分片失败: "+partial, err)
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
		return written, offset, api.WrapError(api.CodeNetwork, "下载", "传输中断: "+partial, copyErr)
	}
	return written, offset, nil
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
