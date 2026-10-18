package download

import (
	"bytes"
	"context"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/azazo1/tucao/cli/internal/api"
)

// newServer 起一个支持 Range 的媒体服务器.
func newServer(t *testing.T, payload []byte, supportRange bool) *httptest.Server {
	t.Helper()
	return httptest.NewServer(http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
		if !supportRange {
			// 忽略 Range, 每次整份返回, 模拟不支持断点续传的源.
			request.Header.Del("range")
			writer.Header().Set("content-type", "video/mp4")
			writer.WriteHeader(http.StatusOK)
			_, _ = writer.Write(payload)
			return
		}
		writer.Header().Set("content-type", "video/mp4")
		http.ServeContent(writer, request, "sample.mp4", time.Time{}, strings.NewReader(string(payload)))
	}))
}

func TestFileDownloadsNewFile(t *testing.T) {
	payload := []byte(strings.Repeat("tucao", 100))
	server := newServer(t, payload, true)
	defer server.Close()

	target := filepath.Join(t.TempDir(), "video.mp4")
	var lastReceived, lastTotal int64
	result, err := File(context.Background(), server.Client(), server.URL+"/sample.mp4", target, Options{
		Progress: func(received, total int64) {
			lastReceived, lastTotal = received, total
		},
	})
	if err != nil {
		t.Fatalf("下载失败: %v", err)
	}
	if result.Bytes != int64(len(payload)) || lastReceived != int64(len(payload)) {
		t.Fatalf("下载字节数不正确: %+v", result)
	}
	if lastTotal != int64(len(payload)) {
		t.Fatalf("总长度应已知: %d", lastTotal)
	}
	data, err := os.ReadFile(target)
	if err != nil {
		t.Fatalf("读取下载文件失败: %v", err)
	}
	if string(data) != string(payload) {
		t.Fatal("下载内容不一致")
	}
	if _, err := os.Stat(target + ".part"); !os.IsNotExist(err) {
		t.Fatalf("临时文件应被清理: %v", err)
	}
}

func TestFileResumesFromPartial(t *testing.T) {
	payload := []byte(strings.Repeat("abcdefgh", 200))
	server := newServer(t, payload, true)
	defer server.Close()

	target := filepath.Join(t.TempDir(), "video.mp4")
	partial := target + ".part"
	if err := os.WriteFile(partial, payload[:500], 0o644); err != nil {
		t.Fatalf("写入分片失败: %v", err)
	}
	result, err := File(context.Background(), server.Client(), server.URL+"/sample.mp4", target, Options{})
	if err != nil {
		t.Fatalf("续传失败: %v", err)
	}
	if !result.Resumed {
		t.Fatal("应从断点续传")
	}
	data, err := os.ReadFile(target)
	if err != nil {
		t.Fatalf("读取下载文件失败: %v", err)
	}
	if string(data) != string(payload) {
		t.Fatalf("续传后内容不一致: %d 字节", len(data))
	}
}

func TestFileFallsBackWhenRangeUnsupported(t *testing.T) {
	payload := []byte(strings.Repeat("xyz", 100))
	server := newServer(t, payload, false)
	defer server.Close()

	target := filepath.Join(t.TempDir(), "video.mp4")
	if err := os.WriteFile(target+".part", payload[:100], 0o644); err != nil {
		t.Fatalf("写入分片失败: %v", err)
	}
	result, err := File(context.Background(), server.Client(), server.URL+"/sample.mp4", target, Options{})
	if err != nil {
		t.Fatalf("不支持 Range 时应回退重下: %v", err)
	}
	if result.Resumed {
		t.Fatal("服务器不支持 Range 时不应标记为续传")
	}
	data, err := os.ReadFile(target)
	if err != nil {
		t.Fatalf("读取下载文件失败: %v", err)
	}
	if string(data) != string(payload) {
		t.Fatalf("回退下载内容不一致: %d 字节", len(data))
	}
}

func TestFileRejectsExistingTarget(t *testing.T) {
	payload := []byte("data")
	server := newServer(t, payload, true)
	defer server.Close()

	target := filepath.Join(t.TempDir(), "video.mp4")
	if err := os.WriteFile(target, []byte("旧文件"), 0o644); err != nil {
		t.Fatalf("写入旧文件失败: %v", err)
	}
	_, err := File(context.Background(), server.Client(), server.URL+"/sample.mp4", target, Options{})
	if err == nil {
		t.Fatal("目标存在且未指定覆盖时应报错")
	}
	if api.CodeOf(err) != api.CodeInvalidInput {
		t.Fatalf("应为参数错误: %v", err)
	}
	if _, err := File(context.Background(), server.Client(), server.URL+"/sample.mp4", target, Options{Overwrite: true}); err != nil {
		t.Fatalf("指定覆盖后应成功: %v", err)
	}
}

func TestFileRejectsHTMLResponse(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
		writer.Header().Set("content-type", "text/html; charset=utf-8")
		writer.WriteHeader(http.StatusOK)
		_, _ = writer.Write([]byte("<html>防盗链拦截</html>"))
	}))
	defer server.Close()

	target := filepath.Join(t.TempDir(), "video.mp4")
	_, err := File(context.Background(), server.Client(), server.URL+"/x.mp4", target, Options{})
	if err == nil {
		t.Fatal("网页响应应当被拒绝")
	}
	if api.CodeOf(err) != api.CodeUpstream {
		t.Fatalf("应为上游错误: %v", err)
	}
	if _, statErr := os.Stat(target); !os.IsNotExist(statErr) {
		t.Fatalf("失败时不应落下目标文件: %v", statErr)
	}
}

func TestFileRejectsPlaylistAndBadSource(t *testing.T) {
	client := &http.Client{}
	target := filepath.Join(t.TempDir(), "video.mp4")
	for _, source := range []string{"", "ftp://x/a.mp4", "https://x/a.m3u8"} {
		if _, err := File(context.Background(), client, source, target, Options{}); err == nil {
			t.Fatalf("非法地址应被拒绝: %q", source)
		} else if api.CodeOf(err) != api.CodeInvalidInput {
			t.Fatalf("应为参数错误: %v", err)
		}
	}
}

func TestFileReportsUpstreamStatus(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
		writer.WriteHeader(http.StatusForbidden)
	}))
	defer server.Close()
	target := filepath.Join(t.TempDir(), "video.mp4")
	_, err := File(context.Background(), server.Client(), server.URL+"/x.mp4", target, Options{})
	if err == nil {
		t.Fatal("403 应当报错")
	}
	if api.CodeOf(err) != api.CodeUpstream {
		t.Fatalf("应为上游错误: %v", err)
	}
}

func TestFileRetriesAfterTruncatedConnection(t *testing.T) {
	payload := []byte(strings.Repeat("tucao-download-", 4096))
	var calls int32
	server := httptest.NewServer(http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
		attempt := atomic.AddInt32(&calls, 1)
		writer.Header().Set("content-type", "video/mp4")
		if attempt == 1 {
			// 第一次只发一半就把连接掐掉, 模拟传输中断.
			writer.Header().Set("content-length", fmt.Sprint(len(payload)))
			writer.WriteHeader(http.StatusOK)
			_, _ = writer.Write(payload[:len(payload)/2])
			if flusher, ok := writer.(http.Flusher); ok {
				flusher.Flush()
			}
			panic(http.ErrAbortHandler)
		}
		// 第二次正常响应 Range 请求.
		http.ServeContent(writer, request, "sample.mp4", time.Time{}, bytes.NewReader(payload))
	}))
	defer server.Close()

	target := filepath.Join(t.TempDir(), "video.mp4")
	result, err := File(context.Background(), server.Client(), server.URL+"/sample.mp4", target, Options{Retries: 3})
	if err != nil {
		t.Fatalf("断流后应自动续传: %v", err)
	}
	if result.Retried == 0 {
		t.Fatal("应记录续传次数")
	}
	if result.Bytes != int64(len(payload)) {
		t.Fatalf("续传后字节数不正确: %d != %d", result.Bytes, len(payload))
	}
	data, err := os.ReadFile(target)
	if err != nil {
		t.Fatalf("读取文件失败: %v", err)
	}
	if string(data) != string(payload) {
		t.Fatalf("续传后内容不一致: %d 字节", len(data))
	}
}

func TestFileGivesUpAfterRetries(t *testing.T) {
	var calls int32
	server := httptest.NewServer(http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
		atomic.AddInt32(&calls, 1)
		writer.Header().Set("content-type", "video/mp4")
		writer.Header().Set("content-length", "1000")
		writer.WriteHeader(http.StatusOK)
		// 先发一小段再断开, 与服务端中途掐断连接的表现一致.
		_, _ = writer.Write(bytes.Repeat([]byte("x"), 64))
		if flusher, ok := writer.(http.Flusher); ok {
			flusher.Flush()
		}
		panic(http.ErrAbortHandler)
	}))
	defer server.Close()

	target := filepath.Join(t.TempDir(), "video.mp4")
	_, err := File(context.Background(), server.Client(), server.URL+"/x.mp4", target, Options{Retries: 2})
	if err == nil {
		t.Fatal("一直断流时应当报错")
	}
	if api.CodeOf(err) != api.CodeNetwork {
		t.Fatalf("应为网络错误: %v", err)
	}
	if !strings.Contains(err.Error(), "续传") {
		t.Fatalf("错误信息应提示可以续传: %v", err)
	}
	if got := atomic.LoadInt32(&calls); got != 3 {
		t.Fatalf("应尝试 3 次 (首次加 2 次重试), 实际 %d", got)
	}
	if _, statErr := os.Stat(target + ".part"); statErr != nil {
		t.Fatalf("失败时应保留分片以便续传: %v", statErr)
	}
}
