package api

import (
	"context"
	"regexp"
	"strconv"
	"strings"
	"time"
)

// 站点把统计数字写成 javascript 赋值, 这里直接把键值对解析出来.
var statsCallPattern = regexp.MustCompile(`\$\('#([A-Za-z0-9_]+)'\)\.html\('([^']*)'\)`)

// ParseStatsScript 解析统计脚本里的赋值语句.
func ParseStatsScript(raw string) map[string]string {
	values := map[string]string{}
	for _, match := range statsCallPattern.FindAllStringSubmatch(raw, -1) {
		values[match[1]] = match[2]
	}
	return values
}

// OnlineCount 取当前正在观看该内容的人数.
//
// 站点用 hid 拼接内容模型 id 作为 cid, v=0 时只返回数字.
func (c *Client) OnlineCount(ctx context.Context, hid string, modelID int) (*int, error) {
	if hid == "" {
		return nil, nil
	}
	query := buildQuery(
		"cid", OnlineCID(hid, modelID),
		"v", 0,
		"t", strconv.FormatInt(time.Now().UnixMilli(), 10),
	)
	values, err := c.fetchStatsScript(ctx, PathOnline, query)
	if err != nil {
		return nil, err
	}
	return numberOrNil(values["olThis"]), nil
}

// SiteOnline 取总站实时在线人数与在线播放器数.
//
// 该接口传空 cid 时返回整站数据.
func (c *Client) SiteOnline(ctx context.Context) (online *int, players *int, err error) {
	query := buildQuery(
		"cid", "",
		"v", 0,
		"t", strconv.FormatInt(time.Now().UnixMilli(), 10),
	)
	values, err := c.fetchStatsScript(ctx, PathOnline, query)
	if err != nil {
		return nil, nil, err
	}
	return numberOrNil(values["olAll"]), numberOrNil(values["olALL_player"]), nil
}

// ContentCounts 取总播放量与追番数.
func (c *Client) ContentCounts(ctx context.Context, hid string, modelID int) (playCount *int, favoriteCount *int, err error) {
	path, query := APIPath("count", buildQuery("id", hid, "modelid", modelID))
	values, err := c.fetchStatsScript(ctx, path, query)
	if err != nil {
		return nil, nil, err
	}
	return numberOrNil(values["hits"]), numberOrNil(values["fav"]), nil
}

func (c *Client) fetchStatsScript(ctx context.Context, path string, query map[string][]string) (map[string]string, error) {
	raw, err := c.Get(ctx, c.SiteURL(path), query)
	if err != nil {
		return nil, err
	}
	return ParseStatsScript(string(raw)), nil
}

// numberOrNil 从可能带单位的文本里取出数字.
func numberOrNil(raw string) *int {
	digits := strings.Map(func(symbol rune) rune {
		if symbol >= '0' && symbol <= '9' {
			return symbol
		}
		return -1
	}, raw)
	if digits == "" {
		return nil
	}
	value, err := strconv.Atoi(digits)
	if err != nil {
		return nil
	}
	return &value
}
