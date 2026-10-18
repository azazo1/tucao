package api

import (
	"context"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"sync/atomic"
	"testing"
)

func discardClient(t *testing.T, baseURL string) *Client {
	t.Helper()
	client := NewClient(baseURL, nil, slog.New(slog.NewTextHandler(io.Discard, nil)))
	return client
}

func TestOnlineCountKeepsVersionZero(t *testing.T) {
	var rawQuery string
	var path string
	server := httptest.NewServer(http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
		rawQuery = request.URL.RawQuery
		path = request.URL.Path
		_, _ = writer.Write([]byte(`$('#olThis').html('42');`))
	}))
	defer server.Close()

	client := discardClient(t, server.URL+"/")
	value, err := client.OnlineCount(context.Background(), "4107864", VideoModelID)
	if err != nil {
		t.Fatalf("读取在线人数失败: %v", err)
	}
	if value == nil || *value != 42 {
		t.Fatalf("在线人数解析错误: %v", value)
	}
	if path != "/ol.php" {
		t.Fatalf("请求路径错误: %s", path)
	}
	if !strings.Contains(rawQuery, "v=0") {
		t.Fatalf("查询参数缺少 v=0, 站点会返回轮询脚本: %s", rawQuery)
	}
	if !strings.Contains(rawQuery, "cid=410786411") {
		t.Fatalf("cid 拼接错误: %s", rawQuery)
	}
}

func TestSiteOnlineOmitsCID(t *testing.T) {
	var rawQuery string
	server := httptest.NewServer(http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
		rawQuery = request.URL.RawQuery
		_, _ = writer.Write([]byte(`$('#olAll').html('1,751');$('#olALL_player').html('958');`))
	}))
	defer server.Close()

	client := discardClient(t, server.URL+"/")
	online, players, err := client.SiteOnline(context.Background())
	if err != nil {
		t.Fatalf("读取站点在线人数失败: %v", err)
	}
	if online == nil || *online != 1751 || players == nil || *players != 958 {
		t.Fatalf("整站在线人数解析错误: %v %v", online, players)
	}
	if strings.Contains(rawQuery, "cid=") {
		t.Fatalf("整站查询不应带 cid: %s", rawQuery)
	}
}

func TestContentCounts(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
		if request.URL.Query().Get("op") != "count" {
			t.Errorf("缺少 op=count: %s", request.URL.RawQuery)
		}
		_, _ = writer.Write([]byte(`$('#hits').html('163,565');$('#fav').html('29');`))
	}))
	defer server.Close()

	client := discardClient(t, server.URL+"/")
	playCount, favoriteCount, err := client.ContentCounts(context.Background(), "4107864", VideoModelID)
	if err != nil {
		t.Fatalf("读取统计失败: %v", err)
	}
	if playCount == nil || *playCount != 163565 {
		t.Fatalf("播放量解析错误: %v", playCount)
	}
	if favoriteCount == nil || *favoriteCount != 29 {
		t.Fatalf("追番数解析错误: %v", favoriteCount)
	}
}

func TestDanmakuSendParameters(t *testing.T) {
	var (
		rawQuery string
		form     url.Values
		header   http.Header
		method   string
	)
	server := httptest.NewServer(http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
		method = request.Method
		rawQuery = request.URL.RawQuery
		header = request.Header
		body, _ := io.ReadAll(request.Body)
		form, _ = url.ParseQuery(string(body))
		_, _ = writer.Write([]byte("1"))
	}))
	defer server.Close()

	client := discardClient(t, server.URL+"/")
	if _, err := client.DanmakuSend(context.Background(), 11, "4107864", 1, "前方高能", 12.5, 16711680, 5, 25); err != nil {
		t.Fatalf("发送弹幕失败: %v", err)
	}
	if method != http.MethodPost {
		t.Fatalf("弹幕接口应使用 POST: %s", method)
	}
	if !strings.Contains(rawQuery, "m=mukio") || !strings.Contains(rawQuery, "a=post") {
		t.Fatalf("弹幕接口查询参数错误: %s", rawQuery)
	}
	if !strings.Contains(rawQuery, "playerID=11-4107864-1-1") {
		t.Fatalf("playerID 错误: %s", rawQuery)
	}
	if header.Get("content-type") != "application/x-www-form-urlencoded" {
		t.Fatalf("表单类型错误: %s", header.Get("content-type"))
	}
	if header.Get("cookie") != "tucao_verify=ok" {
		t.Fatalf("弹幕接口需要带 tucao_verify: %s", header.Get("cookie"))
	}
	want := map[string]string{
		"cid":     "4107864",
		"stime":   "12.5",
		"message": "前方高能",
		"size":    "25",
		"mode":    "5",
		"color":   "16711680",
	}
	for key, value := range want {
		if form.Get(key) != value {
			t.Fatalf("表单字段 %s = %q, 期望 %q", key, form.Get(key), value)
		}
	}
}

func TestReplySendParameters(t *testing.T) {
	var (
		rawQuery string
		form     url.Values
	)
	server := httptest.NewServer(http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
		rawQuery = request.URL.RawQuery
		body, _ := io.ReadAll(request.Body)
		form, _ = url.ParseQuery(string(body))
		_, _ = writer.Write([]byte("1"))
	}))
	defer server.Close()

	client := discardClient(t, server.URL+"/")
	if _, err := client.ReplySend(context.Background(), 11, "4107869", "同意", 316510, 453580); err != nil {
		t.Fatalf("发送评论失败: %v", err)
	}
	query, _ := url.ParseQuery(rawQuery)
	if query.Get("commentid") != "content_11-4107869-1" {
		t.Fatalf("评论楼层 id 错误: %s", query.Get("commentid"))
	}
	if query.Get("id") != "316510" || query.Get("replyuid") != "453580" {
		t.Fatalf("回复参数应放在查询串: %s", rawQuery)
	}
	if form.Get("content") != "同意" {
		t.Fatalf("评论内容应放在表单: %v", form)
	}
}

func TestReadRequestsRetryButWritesDoNot(t *testing.T) {
	var readCalls, writeCalls int32
	server := httptest.NewServer(http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
		if request.Method == http.MethodPost {
			atomic.AddInt32(&writeCalls, 1)
		} else {
			atomic.AddInt32(&readCalls, 1)
		}
		writer.WriteHeader(http.StatusInternalServerError)
	}))
	defer server.Close()

	client := discardClient(t, server.URL+"/")
	client.Retries = 2
	if _, err := client.Get(context.Background(), server.URL+"/ol.php", nil); err == nil {
		t.Fatal("5xx 应当报错")
	}
	if got := atomic.LoadInt32(&readCalls); got != 3 {
		t.Fatalf("只读请求应重试到 3 次, 实际 %d", got)
	}
	if _, err := client.PostForm(context.Background(), server.URL+"/post.php", nil, url.Values{"message": {"x"}}); err == nil {
		t.Fatal("写请求失败也应当报错")
	}
	if got := atomic.LoadInt32(&writeCalls); got != 1 {
		t.Fatalf("写请求不应重试, 实际 %d 次", got)
	}
}

func TestNotFoundAndUpstreamErrors(t *testing.T) {
	responses := map[string]int{"/missing": http.StatusNotFound, "/broken": http.StatusServiceUnavailable}
	server := httptest.NewServer(http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
		writer.WriteHeader(responses[request.URL.Path])
	}))
	defer server.Close()

	client := discardClient(t, server.URL+"/")
	client.Retries = 0
	if _, err := client.Get(context.Background(), server.URL+"/missing", nil); CodeOf(err) != CodeNotFound {
		t.Fatalf("404 应映射为 not_found: %v", err)
	}
	if _, err := client.Get(context.Background(), server.URL+"/broken", nil); CodeOf(err) != CodeUpstream {
		t.Fatalf("5xx 应映射为 upstream_error: %v", err)
	}
	if _, err := client.Get(context.Background(), "http://127.0.0.1:1/x", nil); CodeOf(err) != CodeNetwork {
		t.Fatalf("连接失败应映射为 network_error: %v", err)
	}
}

func TestDecodeJSONObjectToleratesWrapper(t *testing.T) {
	payload, err := DecodeJSONObject([]byte("\ufeff({\"status\":1})"))
	if err != nil {
		t.Fatalf("宽松解析失败: %v", err)
	}
	if fmt.Sprint(payload["status"]) != "1" {
		t.Fatalf("解析结果不正确: %v", payload)
	}
	if _, err := DecodeJSONObject([]byte("   ")); err == nil {
		t.Fatal("空内容应当报错")
	}
	if _, err := DecodeJSONObject([]byte("不是 json")); err == nil {
		t.Fatal("非法内容应当报错")
	}
}

func TestClientSendsSiteHeaders(t *testing.T) {
	var header http.Header
	server := httptest.NewServer(http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
		header = request.Header
		_, _ = fmt.Fprint(writer, "ok")
	}))
	defer server.Close()

	client := discardClient(t, server.URL+"/")
	if _, err := client.Get(context.Background(), server.URL+"/x", nil); err != nil {
		t.Fatalf("请求失败: %v", err)
	}
	if header.Get("user-agent") != MobileUserAgent {
		t.Fatalf("默认应使用移动端 UA: %s", header.Get("user-agent"))
	}
	if header.Get("referer") == "" {
		t.Fatal("请求应带 referer")
	}
	if _, err := client.Get(context.Background(), server.URL+"/x", nil, DesktopUA()); err != nil {
		t.Fatalf("请求失败: %v", err)
	}
	if header.Get("user-agent") != DesktopUserAgent {
		t.Fatalf("页面请求应使用桌面 UA: %s", header.Get("user-agent"))
	}
}
