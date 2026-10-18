package api

import (
	"context"
	"encoding/json"
	"regexp"
	"strings"
	"time"

	"github.com/azazo1/tucao/cli/internal/model"
)

var (
	// 登录失败提示, 与安卓端的判断一致.
	loginFailurePattern = regexp.MustCompile(`密码错误|登录失败|不存在`)
	// 表单错误提示.
	formErrorPattern = regexp.MustCompile(`错误|失败|不正确|不存在|不能为空|过期|不成功|未成功|不允许`)
	// 脚本里的 showmessage 提示.
	showMessagePattern = regexp.MustCompile(`showmessage\('([^']+)'`)
)

// UserInfo 查询当前登录状态, 未登录时返回 nil.
func (c *Client) UserInfo(ctx context.Context) (*model.User, error) {
	path, query := APIPath("user", nil)
	raw, err := c.Get(ctx, c.SiteURL(path), query)
	if err != nil {
		return nil, err
	}
	text := strings.TrimSpace(strings.TrimPrefix(string(raw), "\ufeff"))
	if text == "" {
		return nil, nil
	}
	var payload map[string]any
	if err := json.Unmarshal([]byte(text), &payload); err != nil {
		return nil, WrapError(CodeUpstream, "查询登录状态", "站点返回内容无法解析", err)
	}
	if isLogin, ok := payload["islogin"].(bool); ok && !isLogin {
		return nil, nil
	}
	// 接口在不同登录状态下返回的字段层级不一致, 逐层向下找.
	var data any = payload
	if value, ok := payload["data"]; ok && value != nil {
		data = value
	} else if value, ok := payload["result"]; ok && value != nil {
		data = value
	}
	values, ok := data.(map[string]any)
	if !ok {
		return nil, nil
	}
	if values["userid"] == nil && values["uid"] == nil {
		for _, value := range values {
			nested, ok := value.(map[string]any)
			if !ok {
				continue
			}
			if nested["userid"] != nil || nested["uid"] != nil {
				values = nested
				break
			}
		}
	}
	user := parseUser(values)
	if user.UserID == 0 && user.UserName == "" {
		return nil, nil
	}
	return user, nil
}

func parseUser(values map[string]any) *model.User {
	return &model.User{
		UserID:    intValueOf(values, "userid", "uid", "user_id"),
		UserName:  stringValueOf(values, "username", "name", "user_name"),
		Nickname:  stringValueOf(values, "nickname", "nick_name"),
		Avatar:    stringValueOf(values, "avatar", "face"),
		GroupName: stringValueOf(values, "groupname"),
		Credit:    intValueOf(values, "credit"),
	}
}

func stringValueOf(values map[string]any, keys ...string) string {
	for _, key := range keys {
		value, ok := values[key]
		if !ok || value == nil {
			continue
		}
		if text, ok := value.(string); ok {
			return text
		}
	}
	return ""
}

func intValueOf(values map[string]any, keys ...string) int {
	for _, key := range keys {
		value, ok := values[key]
		if !ok || value == nil {
			continue
		}
		switch typed := value.(type) {
		case string:
			parsed := 0
			for _, symbol := range typed {
				if symbol < '0' || symbol > '9' {
					return parsed
				}
				parsed = parsed*10 + int(symbol-'0')
			}
			return parsed
		case float64:
			return int(typed)
		}
	}
	return 0
}

// Login 登录.
//
// 站点是 discuz 表单登录, 成功后由 cookie 维持会话.
// 必须带 dosubmit, 否则站点把请求当成没点登录按钮, 直接返回登录页.
func (c *Client) Login(ctx context.Context, username, password, questionID, answer string) (string, error) {
	path, query := IndexPath("member", "index", "login", nil)
	form := formValues(map[string]string{
		"username":   username,
		"password":   password,
		"questionid": questionID,
		"answer":     answer,
		"cookietime": "2592000",
		"dosubmit":   "1",
	})
	raw, err := c.PostForm(ctx, c.SiteURL(path), query, form)
	if err != nil {
		return "", err
	}
	return string(raw), nil
}

// Logout 退出登录.
func (c *Client) Logout(ctx context.Context) error {
	path, query := IndexPath("member", "index", "logout", formValues(map[string]string{
		"forward": "",
		"siteid":  "1",
	}))
	_, err := c.Get(ctx, c.SiteURL(path), query)
	return err
}

// Register 注册.
//
// 字段与站点注册表单一致, 成功时站点返回跳转脚本, 失败时返回带提示的页面.
func (c *Client) Register(ctx context.Context, username, nickname, email, password, confirmPassword string) (string, error) {
	path, query := IndexPath("member", "index", "register", formValues(map[string]string{"siteid": "1"}))
	form := formValues(map[string]string{
		"username":   username,
		"nickname":   nickname,
		"email":      email,
		"password":   password,
		"pwdconfirm": confirmPassword,
		"dosubmit":   "1",
	})
	raw, err := c.PostForm(ctx, c.SiteURL(path), query, form)
	if err != nil {
		return "", err
	}
	return string(raw), nil
}

// ChangePassword 修改密码, 需要登录态.
func (c *Client) ChangePassword(ctx context.Context, oldPassword, newPassword, confirmPassword string) (string, error) {
	path, query := IndexPath("member", "index", "account_manage_password", formValues(map[string]string{"t": "account"}))
	form := formValues(map[string]string{
		"info[password]":      oldPassword,
		"info[newpassword]":   newPassword,
		"info[renewpassword]": confirmPassword,
		"dosubmit":            "提交",
	})
	raw, err := c.PostForm(ctx, c.SiteURL(path), query, form)
	if err != nil {
		return "", err
	}
	return string(raw), nil
}

// ForgotPassword 通过邮箱找回密码.
//
// 表单只有邮箱与验证码两项, 站点把新密码发到邮箱;
// 验证码与提交必须共用同一份 cookie, 否则站点判为验证码错误.
func (c *Client) ForgotPassword(ctx context.Context, email, code string) (model.FormResult, error) {
	path, query := IndexPath("member", "index", "public_forget_password", formValues(map[string]string{"siteid": "1"}))
	form := formValues(map[string]string{
		"email":    email,
		"code":     code,
		"dosubmit": "提交",
	})
	raw, err := c.PostForm(ctx, c.SiteURL(path), query, form)
	if err != nil {
		return model.FormResult{}, err
	}
	return ParseFormResponse(string(raw)), nil
}

// CheckCode 拉取图形验证码图片.
//
// 站点按 cookie 里的会话生成验证码, 因此必须与后续提交共用同一个客户端.
func (c *Client) CheckCode(ctx context.Context) ([]byte, error) {
	path, query := APIPath("checkcode", formValues(map[string]string{
		"code_len":   "4",
		"font_size":  "14",
		"width":      "118",
		"height":     "40",
		"font_color": "",
		"background": "",
		"_":          itoa(int(time.Now().UnixMicro())),
	}))
	payload, err := c.Get(ctx, c.SiteURL(path), query, RawBytes(), Header("cache-control", "no-cache"))
	if err != nil {
		return nil, err
	}
	if len(payload) == 0 {
		return nil, NewError(CodeUpstream, "获取验证码", "站点未返回有效的验证码图片")
	}
	return payload, nil
}

// ParseFormResponse 解析站点表单提示页.
//
// 成功标记只从正文读取, 不执行或采信脚本里的内容.
func ParseFormResponse(raw string) model.FormResult {
	document, err := parseDocument(raw)
	if err != nil {
		return model.FormResult{Status: model.FormUnknown, Message: "站点返回了未识别的响应, 请稍后重试"}
	}
	document.Find("script, style, noscript").Remove()
	body := document.Find("body").First()
	text := cleanSpace(document.Text())
	if text == "" || body.Length() == 0 ||
		body.Find("form, input").Length() > 0 || len([]rune(text)) > 500 {
		return model.FormResult{Status: model.FormUnknown, Message: "站点返回了未识别的响应, 请稍后重试"}
	}
	if formErrorPattern.MatchString(text) {
		return model.FormResult{Status: model.FormRejected, Message: text}
	}
	if strings.Contains(text, "成功") {
		return model.FormResult{Status: model.FormSuccess, Message: text}
	}
	// 实测失败页通过 history.back() 返回表单, 提示不限于固定错误关键词.
	if body.Find(`a[href^="javascript:history.back"]`).Length() > 0 {
		return model.FormResult{Status: model.FormRejected, Message: text}
	}
	return model.FormResult{Status: model.FormUnknown, Message: "站点返回了未识别的响应, 请稍后重试"}
}

// LoginFailure 判断登录响应是否失败, 失败时返回原因.
func LoginFailure(raw string) string {
	if loginFailurePattern.MatchString(raw) {
		return "用户名或密码错误"
	}
	return ""
}

// FormFailure 从表单响应里提取失败原因, 明确成功时返回空串.
func FormFailure(raw, fallback string) string {
	// 脚本里的 showmessage 只作为错误提示, 不能作为成功凭据.
	if match := showMessagePattern.FindStringSubmatch(raw); match != nil {
		if message := cleanSpace(match[1]); message != "" {
			return message
		}
	}
	response := ParseFormResponse(raw)
	if response.IsSuccess() {
		return ""
	}
	if response.Status == model.FormRejected {
		return response.Message
	}
	return fallback
}
