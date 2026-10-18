package api

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"
)

// 站点常量, 与安卓端 Constants 一致.
const (
	// APIKey 是官方安卓端使用的接口密钥, 全站公开.
	APIKey = "25tids8f1ew1821ed"

	// 站点视频内容模型固定为 11, 档案资讯固定为 18.
	VideoModelID   = 11
	ArticleModelID = 18

	// 档案详情页取不到分区 id 时使用的兜底值.
	ArticleCommentTypeID = 41
)

// 站点按 UA 返回不同内容, 因此区分两套 UA.
const (
	// MobileUserAgent 用于 api_v2 接口.
	MobileUserAgent = "Mozilla/5.0 (Linux; Android 12; Pixel 6) AppleWebKit/537.36 " +
		"(KHTML, like Gecko) Chrome/120.0.6099.230 Mobile Safari/537.36"

	// DesktopUserAgent 用于抓页面, 只有桌面 UA 才能拿到完整榜单.
	DesktopUserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 " +
		"(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
)

// Client 是站点请求客户端.
//
// 挂载 UA, Referer 与 cookie jar, 统一超时与只读请求的重试策略.
type Client struct {
	BaseURL   string
	HTTP      *http.Client
	Jar       http.CookieJar
	Timeout   time.Duration
	Retries   int
	UserAgent string
	Logger    *slog.Logger
}

// NewClient 构造默认客户端, jar 由调用方注入以便持久化登录态.
func NewClient(baseURL string, jar http.CookieJar, logger *slog.Logger) *Client {
	if logger == nil {
		logger = slog.Default()
	}
	client := &Client{
		BaseURL:   baseURL,
		Jar:       jar,
		Timeout:   30 * time.Second,
		Retries:   1,
		UserAgent: MobileUserAgent,
		Logger:    logger,
	}
	client.HTTP = &http.Client{
		Jar:     jar,
		Timeout: client.Timeout,
	}
	return client
}

// SetTimeout 更新请求超时, 需要同时更新底层客户端.
func (c *Client) SetTimeout(timeout time.Duration) {
	if timeout <= 0 {
		return
	}
	c.Timeout = timeout
	c.HTTP.Timeout = timeout
}

// SiteURL 拼接站点地址, 传入的路径不带前导斜杠.
func (c *Client) SiteURL(path string) string {
	return strings.TrimSuffix(c.BaseURL, "/") + "/" + strings.TrimPrefix(path, "/")
}

// APIURL 拼接 api_v2 接口地址.
func (c *Client) APIURL(path string) string {
	return c.SiteURL("api_v2/" + strings.TrimPrefix(path, "/"))
}

type requestOptions struct {
	userAgent string
	headers   map[string]string
	rawBytes  bool
}

// RequestOption 用于调整单次请求的行为.
type RequestOption func(*requestOptions)

// DesktopUA 让本次请求使用桌面 UA.
func DesktopUA() RequestOption {
	return func(options *requestOptions) { options.userAgent = DesktopUserAgent }
}

// Header 追加或覆盖一个请求头.
func Header(key, value string) RequestOption {
	return func(options *requestOptions) {
		if options.headers == nil {
			options.headers = map[string]string{}
		}
		options.headers[key] = value
	}
}

// RawBytes 表示按二进制读取响应, 用于验证码图片等.
func RawBytes() RequestOption {
	return func(options *requestOptions) { options.rawBytes = true }
}

func buildRequestOptions(options []RequestOption) requestOptions {
	var result requestOptions
	for _, option := range options {
		option(&result)
	}
	return result
}

// Get 发起只读请求, 默认按配置重试.
func (c *Client) Get(ctx context.Context, rawURL string, query url.Values, options ...RequestOption) ([]byte, error) {
	return c.do(ctx, http.MethodGet, rawURL, query, "", options...)
}

// PostForm 发起表单请求, 默认不重试, 避免重复写操作.
func (c *Client) PostForm(ctx context.Context, rawURL string, query url.Values, form url.Values, options ...RequestOption) ([]byte, error) {
	return c.do(ctx, http.MethodPost, rawURL, query, form.Encode(), options...)
}

func (c *Client) do(ctx context.Context, method, rawURL string, query url.Values, body string, options ...RequestOption) ([]byte, error) {
	settings := buildRequestOptions(options)
	target := rawURL
	if len(query) > 0 {
		target += "?" + query.Encode()
	}
	userAgent := settings.userAgent
	if userAgent == "" {
		userAgent = c.UserAgent
	}

	action := http.MethodGet + " " + rawURL
	attempts := 1
	if method == http.MethodGet {
		attempts += c.Retries
	}
	if attempts < 1 {
		attempts = 1
	}

	var lastErr error
	for attempt := 1; attempt <= attempts; attempt++ {
		if err := ctx.Err(); err != nil {
			return nil, NetworkError(action, err)
		}
		payload, retryable, err := c.attempt(ctx, method, target, body, userAgent, settings)
		if err == nil {
			return payload, nil
		}
		lastErr = err
		if !retryable || attempt == attempts {
			break
		}
		c.Logger.Debug("请求失败, 准备重试", "url", rawURL, "attempt", attempt, "error", err)
		select {
		case <-ctx.Done():
			return nil, NetworkError(action, ctx.Err())
		case <-time.After(time.Duration(attempt) * 500 * time.Millisecond):
		}
	}
	return nil, lastErr
}

func (c *Client) attempt(ctx context.Context, method, target, body, userAgent string, settings requestOptions) ([]byte, bool, error) {
	action := method + " " + target
	var reader io.Reader
	if body != "" {
		reader = strings.NewReader(body)
	}
	request, err := http.NewRequestWithContext(ctx, method, target, reader)
	if err != nil {
		return nil, false, NewError(CodeInvalidInput, action, "请求地址非法: "+err.Error())
	}
	request.Header.Set("user-agent", userAgent)
	request.Header.Set("referer", strings.TrimSuffix(c.BaseURL, "/")+"/")
	request.Header.Set("accept-language", "zh-CN,zh;q=0.9,en;q=0.8")
	if body != "" {
		request.Header.Set("content-type", "application/x-www-form-urlencoded")
	}
	for key, value := range settings.headers {
		request.Header.Set(key, value)
	}

	c.Logger.Debug("请求", "method", method, "url", target)
	response, err := c.HTTP.Do(request)
	if err != nil {
		return nil, true, NetworkError(action, err)
	}
	defer response.Body.Close()

	payload, readErr := io.ReadAll(response.Body)
	if readErr != nil {
		return nil, true, NetworkError(action, readErr)
	}
	c.Logger.Debug("响应", "status", response.StatusCode, "url", target, "length", len(payload))

	if response.StatusCode >= 500 {
		return nil, true, WrapError(CodeUpstream, action,
			fmt.Sprintf("站点返回 %d", response.StatusCode), nil)
	}
	if response.StatusCode == http.StatusNotFound {
		return nil, false, WrapError(CodeNotFound, action, "目标不存在", nil)
	}
	if response.StatusCode >= 400 {
		return nil, false, WrapError(CodeUpstream, action,
			fmt.Sprintf("请求被拒绝, 状态码 %d", response.StatusCode), nil)
	}
	if settings.rawBytes {
		return payload, false, nil
	}
	return payload, false, nil
}

// DecodeJSONObject 宽松解析接口返回的 json 对象.
//
// 站点接口并不总是返回合法 json: 有时带 BOM, 有时用一对括号包裹,
// 这里统一去掉外层干扰再解析.
func DecodeJSONObject(raw []byte) (map[string]any, error) {
	text := strings.TrimSpace(strings.TrimPrefix(string(raw), "\ufeff"))
	if text == "" {
		return nil, NewError(CodeUpstream, "解析响应", "接口返回内容为空")
	}
	if strings.HasPrefix(text, "(") && strings.HasSuffix(text, ")") {
		text = strings.TrimSpace(text[1 : len(text)-1])
	}
	decoder := json.NewDecoder(bytes.NewReader([]byte(text)))
	decoder.UseNumber()
	var parsed map[string]any
	if err := decoder.Decode(&parsed); err != nil {
		return nil, WrapError(CodeUpstream, "解析响应",
			"接口返回内容不是合法 json: "+preview(text), err)
	}
	return parsed, nil
}

// DecodeJSONInto 把响应解析到目标结构.
func DecodeJSONInto(raw []byte, target any) error {
	text := strings.TrimSpace(strings.TrimPrefix(string(raw), "\ufeff"))
	if text == "" {
		return NewError(CodeUpstream, "解析响应", "接口返回内容为空")
	}
	if strings.HasPrefix(text, "(") && strings.HasSuffix(text, ")") {
		text = strings.TrimSpace(text[1 : len(text)-1])
	}
	if err := json.Unmarshal([]byte(text), target); err != nil {
		return WrapError(CodeUpstream, "解析响应",
			"接口返回内容不是合法 json: "+preview(text), err)
	}
	return nil
}

// preview 截取响应开头用于报错, 避免把整页内容写进日志.
func preview(text string) string {
	const limit = 120
	text = strings.Join(strings.Fields(text), " ")
	if len(text) <= limit {
		return text
	}
	cut := limit
	for cut > 0 && !utf8.RuneStart(text[cut]) {
		cut--
	}
	return text[:cut] + "..."
}

// 常用的响应字段取值helper.

// StringField 取字符串字段, 缺失时返回空串.
func StringField(raw map[string]any, key string) string {
	value, ok := raw[key]
	if !ok || value == nil {
		return ""
	}
	switch typed := value.(type) {
	case string:
		return typed
	case json.Number:
		return typed.String()
	case bool:
		return strconv.FormatBool(typed)
	default:
		return fmt.Sprintf("%v", typed)
	}
}

// IntField 取整数字段, 无法解析时返回 0.
func IntField(raw map[string]any, key string) int {
	text := StringField(raw, key)
	if text == "" {
		return 0
	}
	parsed, err := strconv.Atoi(strings.TrimSpace(text))
	if err != nil {
		return 0
	}
	return parsed
}

// FloatField 取浮点字段, 无法解析时返回 0.
func FloatField(raw map[string]any, key string) float64 {
	text := StringField(raw, key)
	if text == "" {
		return 0
	}
	parsed, err := strconv.ParseFloat(strings.TrimSpace(text), 64)
	if err != nil {
		return 0
	}
	return parsed
}
