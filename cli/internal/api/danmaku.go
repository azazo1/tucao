package api

import (
	"context"
	"encoding/xml"
	"net/url"
	"strconv"
	"strings"
	"time"

	"github.com/azazo1/tucao/cli/internal/model"
)

// danmakuXML 是弹幕接口返回的结构: <i><d p="时间,类型,字号,颜色,时间戳">文本</d></i>.
type danmakuXML struct {
	Items []struct {
		P    string `xml:"p,attr"`
		Text string `xml:",chardata"`
	} `xml:"d"`
}

// DanmakuPosition 把站点弹幕类型归一化成渲染位置.
//
// 高级弹幕站点早已不再产生, 统一按滚动处理.
func DanmakuPosition(mode int) string {
	switch mode {
	case 4:
		return model.PositionBottom
	case 5:
		return model.PositionTop
	default:
		return model.PositionScroll
	}
}

// ParseDanmakuXML 解析弹幕 xml.
//
// 空内容或缺 p 属性的节点会被跳过, 与安卓端一致.
func ParseDanmakuXML(raw string) ([]model.Danmaku, error) {
	text := strings.TrimSpace(raw)
	if text == "" {
		return []model.Danmaku{}, nil
	}
	var payload danmakuXML
	if err := xml.Unmarshal([]byte(text), &payload); err != nil {
		return nil, WrapError(CodeUpstream, "解析弹幕", "弹幕内容无法解析", err)
	}
	items := make([]model.Danmaku, 0, len(payload.Items))
	for _, node := range payload.Items {
		content := strings.TrimSpace(node.Text)
		if content == "" || node.P == "" {
			continue
		}
		parts := strings.Split(node.P, ",")
		// 站点格式: 时间, 类型, 字号, 颜色, 时间戳, 弹幕池, 用户id, 行id.
		at := floatField(parts, 0)
		mode := int(intField(parts, 1))
		items = append(items, model.Danmaku{
			Time:      at,
			Mode:      mode,
			Position:  DanmakuPosition(mode),
			FontSize:  int(intField(parts, 2)),
			Color:     int(intField(parts, 3)),
			Timestamp: int64(intField(parts, 4)),
			Text:      content,
		})
	}
	return items, nil
}

func floatField(parts []string, index int) float64 {
	if index >= len(parts) {
		return 0
	}
	value, err := strconv.ParseFloat(strings.TrimSpace(parts[index]), 64)
	if err != nil {
		return 0
	}
	return value
}

func intField(parts []string, index int) int64 {
	if index >= len(parts) {
		return 0
	}
	value, err := strconv.ParseInt(strings.TrimSpace(parts[index]), 10, 64)
	if err != nil {
		return 0
	}
	return value
}

// DanmakuFetch 拉取某一分P的弹幕.
func (c *Client) DanmakuFetch(ctx context.Context, typeID int, hid string, part int) ([]model.Danmaku, error) {
	path, query := IndexPath("mukio", "index", "init", buildQuery(
		"playerID", PlayerID(typeID, hid, part),
		"r", strconv.FormatInt(time.Now().UnixMilli(), 10),
	))
	raw, err := c.Get(ctx, c.SiteURL(path), query)
	if err != nil {
		return nil, err
	}
	return ParseDanmakuXML(string(raw))
}

// DanmakuSend 发送弹幕.
//
// 表单字段与官方客户端一致: playerID 是查询参数,
// cid / stime / message / user / size / mode / color 是表单字段.
// 接口要求登录态, 未登录时返回错误提示.
func (c *Client) DanmakuSend(ctx context.Context, typeID int, hid string, part int, text string, at float64, color, mode, fontSize int) (string, error) {
	path, query := IndexPath("mukio", "index", "post", buildQuery(
		"playerID", PlayerID(typeID, hid, part),
	))
	form := url.Values{}
	form.Set("cid", hid)
	form.Set("stime", strconv.FormatFloat(at, 'f', 1, 64))
	form.Set("message", text)
	form.Set("user", "")
	form.Set("size", strconv.Itoa(fontSize))
	form.Set("mode", strconv.Itoa(mode))
	// 官方按十进制整数提交颜色.
	form.Set("color", strconv.Itoa(color))
	raw, err := c.PostForm(ctx, c.SiteURL(path), query, form, Header("cookie", "tucao_verify=ok"))
	if err != nil {
		return "", err
	}
	return string(raw), nil
}
