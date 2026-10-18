package api

import (
	"context"
	"strconv"
	"strings"

	"github.com/PuerkitoBio/goquery"

	"github.com/azazo1/tucao/cli/internal/model"
)

// HotSearch 拉取热搜榜.
//
// 该页面结构与其他榜单不同, 是关键词列表而不是视频列表,
// 并且按 今天 / 本周 / 本月 / 今年 分组.
func (c *Client) HotSearch(ctx context.Context) ([]model.HotSearchGroup, error) {
	raw, err := c.Get(ctx, c.SiteURL(PathHotSearch), nil, DesktopUA())
	if err != nil {
		return nil, err
	}
	return ParseHotSearchHTML(string(raw)), nil
}

// ParseHotSearchHTML 解析热搜榜页面.
//
// 页面按 div.time_item 分组, 每组有 div.time_title 与若干 div.item,
// 每个 item 的链接结构是 <span>112次</span><b>1</b>无修.
// 次数与排名在独立标签里, 关键词紧跟排名; 关键词本身可能以数字开头
// (例如 1月), 因此不能用一个正则整体切分.
func ParseHotSearchHTML(raw string) []model.HotSearchGroup {
	document, err := parseDocument(raw)
	if err != nil {
		return nil
	}
	groups := []model.HotSearchGroup{}
	document.Find(".time_item").Each(func(_ int, section *goquery.Selection) {
		title := cleanSpace(section.Find(".time_title").First().Text())
		items := parseHotKeywords(section)
		if len(items) == 0 {
			return
		}
		groups = append(groups, model.HotSearchGroup{Title: title, Items: items})
	})
	return groups
}

func parseHotKeywords(section *goquery.Selection) []model.HotKeyword {
	items := []model.HotKeyword{}
	section.Find(".item").Each(func(_ int, item *goquery.Selection) {
		link := item.Find("a").First()
		if link.Length() == 0 {
			return
		}
		countText := cleanSpace(link.Find("span").First().Text())
		rankText := cleanSpace(link.Find("b").First().Text())
		count, err := strconv.Atoi(leadingDigits(countText))
		if err != nil {
			return
		}
		rank, err := strconv.Atoi(strings.TrimSpace(rankText))
		if err != nil {
			return
		}
		keyword := cleanSpace(strings.Replace(strings.Replace(link.Text(), countText, "", 1), rankText, "", 1))
		if keyword == "" {
			return
		}
		items = append(items, model.HotKeyword{Rank: rank, Keyword: keyword, Count: count})
	})
	return items
}

// leadingDigits 取字符串开头连续的数字.
func leadingDigits(raw string) string {
	text := strings.TrimSpace(raw)
	end := 0
	for end < len(text) && text[end] >= '0' && text[end] <= '9' {
		end++
	}
	return text[:end]
}

// UserRank 拉取 u 榜.
//
// 该榜单列的是用户而不是视频, 链接形如 /play/u{uid}/,
// 因此不能复用视频榜单的解析.
func (c *Client) UserRank(ctx context.Context) ([]model.UserRankGroup, error) {
	raw, err := c.Get(ctx, c.SiteURL(PathUserRank), nil, DesktopUA())
	if err != nil {
		return nil, err
	}
	return ParseUserRankHTML(c.BaseURL, string(raw)), nil
}

// ParseUserRankHTML 解析 u 榜页面.
func ParseUserRankHTML(baseURL, raw string) []model.UserRankGroup {
	document, err := parseDocument(raw)
	if err != nil {
		return nil
	}
	groups := []model.UserRankGroup{}
	document.Find(".time_item").Each(func(_ int, section *goquery.Selection) {
		title := cleanSpace(section.Find(".time_title").First().Text())
		items := []model.UserRankItem{}
		seen := map[int]bool{}
		section.Find(".item").Each(func(_ int, item *goquery.Selection) {
			link := item.Find("a.t").First()
			if link.Length() == 0 {
				link = item.Find("a").First()
			}
			if link.Length() == 0 {
				return
			}
			href, _ := link.Attr("href")
			userID := hrefUID(href)
			if userID == 0 || seen[userID] {
				return
			}
			seen[userID] = true
			name := cleanSpace(item.Find(".u").First().Text())
			if name == "" {
				name = cleanSpace(link.Text())
			}
			// 站点只给前三名加类名, 其余条目的序号在无类名的 p 元素里.
			rank := len(items) + 1
			if parsed, err := strconv.Atoi(cleanSpace(item.Find("p").First().Text())); err == nil {
				rank = parsed
			}
			items = append(items, model.UserRankItem{
				UserID:   userID,
				UserName: name,
				Rank:     rank,
				Avatar:   absoluteURL(baseURL, imageSource(item.Find("img").First())),
				Badge:    cleanSpace(item.Find(".c").First().Text()),
			})
		})
		if len(items) == 0 {
			return
		}
		groups = append(groups, model.UserRankGroup{Title: title, Items: items})
	})
	return groups
}

func imageSource(image *goquery.Selection) string {
	if image.Length() == 0 {
		return ""
	}
	src, _ := image.Attr("src")
	return strings.TrimSpace(src)
}
