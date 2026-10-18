package api

import (
	"context"
	"strings"

	"github.com/PuerkitoBio/goquery"

	"github.com/azazo1/tucao/cli/internal/model"
)

// RankType 是站点榜单类型.
//
// 除排行榜外, 站点还有几个同结构的榜单页, 只有分组维度不同;
// u 榜列的是用户而不是视频, 结构不同, 见 UserRank.
type RankType struct {
	// Key 是命令行使用的标识.
	Key string
	// Label 是中文名.
	Label string
	// Path 是榜单页面路径.
	Path string
	// SupportsChannel 表示是否支持按分区筛选, 目前只有排行榜支持.
	SupportsChannel bool
}

// RankTypes 是全部榜单类型, 顺序与命令行帮助一致.
var RankTypes = []RankType{
	{Key: "hot", Label: "排行榜", Path: PathRankHot, SupportsChannel: true},
	{Key: "danmaku", Label: "弹幕榜", Path: PathRankDanmaku},
	{Key: "digg", Label: "神评论", Path: PathRankDigg},
	{Key: "zero", Label: "无人区", Path: PathRankZero},
	{Key: "fav", Label: "追番榜", Path: PathRankFav},
	{Key: "online", Label: "在线榜", Path: PathRankOnline},
	{Key: "update", Label: "今天更新", Path: PathRankNew},
	{Key: "recommend", Label: "今天推荐", Path: PathRankRecommend},
}

// FindRankType 按标识查榜单类型, 同时接受中文名.
func FindRankType(key string) (RankType, bool) {
	text := strings.TrimSpace(key)
	for _, rankType := range RankTypes {
		if rankType.Key == text || rankType.Label == text {
			return rankType, true
		}
	}
	return RankType{}, false
}

// PeriodTitles 是时间维度标题与 period 值的对应关系.
var PeriodTitles = map[string]int{
	"今天": 0,
	"本周": 1,
	"本月": 2,
	"今年": 3,
}

// Rank 拉取榜单.
//
// typeID 为 0 表示全站榜, period 见 PeriodTitles.
// 页面返回全部时间维度, 因此 period 只影响站点返回的默认维度.
func (c *Client) Rank(ctx context.Context, rankType RankType, typeID, period int) ([]model.RankGroup, error) {
	query := buildQuery()
	if rankType.SupportsChannel && typeID > 0 {
		query.Set("p", itoa(typeID))
	}
	if period > 0 {
		query.Set("t", itoa(period))
	}
	raw, err := c.Get(ctx, c.SiteURL(rankType.Path), query, DesktopUA())
	if err != nil {
		return nil, err
	}
	return ParseRankHTML(c.BaseURL, string(raw)), nil
}

// ParseRankHTML 解析榜单页面.
//
// 页面结构为若干 div.time_item, 每个下面是 div.time_title 与 div.list,
// list 里是 div.item: a.p 的封面, a.t 的标题与地址, .i 里的播放数与作者.
// 在线榜这类页面只有一个不带 time_item 的 div.list, 此时整页作为一组.
func ParseRankHTML(baseURL, raw string) []model.RankGroup {
	document, err := parseDocument(raw)
	if err != nil {
		return nil
	}
	sections := document.Find(".time_item")
	if sections.Length() == 0 {
		items := parseRankItems(baseURL, document.Selection)
		if len(items) == 0 {
			return nil
		}
		title := cleanSpace(document.Find(".title a.t").First().Text())
		return []model.RankGroup{{Title: title, Period: -1, Items: items}}
	}
	groups := make([]model.RankGroup, 0, sections.Length())
	sections.Each(func(_ int, section *goquery.Selection) {
		title := cleanSpace(section.Find(".time_title").First().Text())
		items := parseRankItems(baseURL, section)
		if len(items) == 0 {
			return
		}
		period := -1
		if value, ok := PeriodTitles[title]; ok {
			period = value
		}
		groups = append(groups, model.RankGroup{Title: title, Period: period, Items: items})
	})
	return groups
}

// parseRankItems 从一个容器里取出榜单条目, 同一榜单内重复的视频只保留靠前的一次.
func parseRankItems(baseURL string, container *goquery.Selection) []model.Video {
	items := []model.Video{}
	seen := map[string]bool{}
	container.Find(".list .item").EachWithBreak(func(_ int, item *goquery.Selection) bool {
		video, ok := parseRankItem(baseURL, item, seen)
		if ok {
			items = append(items, video)
		}
		return true
	})
	return items
}

func parseRankItem(baseURL string, item *goquery.Selection, seen map[string]bool) (model.Video, bool) {
	link := item.Find("a.t").First()
	if link.Length() == 0 {
		link = item.Find("a").First()
	}
	if link.Length() == 0 {
		return model.Video{}, false
	}
	href, _ := link.Attr("href")
	hid := hrefHID(href)
	if hid == "" || seen[hid] {
		return model.Video{}, false
	}
	seen[hid] = true

	info := item.Find(".i").First()
	userLink := info.Find("a").First()
	userHref, _ := userLink.Attr("href")
	return model.Video{
		HID:       hid,
		Title:     cleanSpace(link.Text()),
		Cover:     coverFromImage(item.Find("img").First()),
		SiteURL:   PlayURL(baseURL, hid),
		PlayCount: firstCount(info.Find("span").First().Text()),
		UserName:  cleanSpace(userLink.Text()),
		UserID:    hrefUID(userHref),
	}, true
}

// coverFromImage 取封面地址.
//
// 站点的 img 的 src 多是统一的占位图, 真实封面写在 style 的
// background-image 里, 缺失时退回 data-img 的第一项, 都没有才用 src.
func coverFromImage(image *goquery.Selection) string {
	if image.Length() == 0 {
		return ""
	}
	style, _ := image.Attr("style")
	if cover := backgroundURL(style); cover != "" {
		return cover
	}
	if dataImage, ok := image.Attr("data-img"); ok {
		for _, part := range strings.Split(dataImage, ",") {
			if trimmed := strings.TrimSpace(part); trimmed != "" {
				return trimmed
			}
		}
	}
	src, _ := image.Attr("src")
	return strings.TrimSpace(src)
}
