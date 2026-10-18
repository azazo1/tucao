package api

import (
	"context"
	"encoding/json"
	"regexp"
	"strings"

	"github.com/azazo1/tucao/cli/internal/model"
)

// digitsPattern 用于校验视频编号.
var digitsPattern = regexp.MustCompile(`^[0-9]+$`)

// FavoriteAdd 调用官网的单向新增收藏接口.
//
// 依据官网播放页的 add_favorite 实现, 未证实个人列表与删除接口,
// 因此只提供新增, 不做猜测实现.
func (c *Client) FavoriteAdd(ctx context.Context, video model.Video) error {
	if !digitsPattern.MatchString(video.HID) || video.TypeID <= 0 || strings.TrimSpace(video.Title) == "" {
		return NewError(CodeInvalidInput, "加入站点收藏", "收藏需要有效的视频 id, 分区和标题")
	}
	path, query := APIPath("add_favorite", buildQuery(
		"title", video.Title,
		"url", "/play/h"+video.HID+"/",
		"contentid", video.HID,
		// 官网视频的内容模型固定为 11, ccatid 才是视频分区.
		"modelid", VideoModelID,
		"ccatid", video.TypeID,
		"cusername", video.UserName,
		"cdescription", video.Description,
		"ccatname", video.TypeName,
		"cuserid", video.UserID,
		"thumb", video.Cover,
	))
	raw, err := c.Get(ctx, c.SiteURL(path), query)
	if err != nil {
		return err
	}
	if !FavoriteSuccess(string(raw)) {
		return NewError(CodeUpstream, "加入站点收藏", "站点未确认收藏成功, 请检查登录状态后重试")
	}
	return nil
}

// FavoriteSuccess 只认 status=1, 空正文与提示页面都不算成功.
func FavoriteSuccess(raw string) bool {
	text := strings.TrimSpace(strings.TrimPrefix(raw, "\ufeff"))
	if strings.HasPrefix(text, "(") && strings.HasSuffix(text, ")") {
		text = strings.TrimSpace(text[1 : len(text)-1])
	}
	var payload struct {
		Status json.RawMessage `json:"status"`
	}
	if err := json.Unmarshal([]byte(text), &payload); err != nil {
		return false
	}
	status := strings.Trim(strings.TrimSpace(string(payload.Status)), `"`)
	return status == "1"
}
