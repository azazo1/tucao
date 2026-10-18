package api

import (
	"context"
	"strconv"

	"github.com/PuerkitoBio/goquery"

	"github.com/azazo1/tucao/cli/internal/model"
)

// 番组索引的筛选项, 与站点上的三栏一致.
var (
	// BgmSeasons 是季度筛选项, 值是月份, 剧场版用 99.
	BgmSeasons = map[string]int{
		"1月":  1,
		"4月":  4,
		"7月":  7,
		"10月": 10,
		"剧场版": 99,
	}
	// BgmYears 是年代筛选项.
	BgmYears = []string{
		"1906-1999", "2000-2009", "2010", "2011", "2012", "2013", "2014",
		"2015", "2016", "2017", "2018", "2019", "2020", "2021", "2022",
		"2023", "2024", "2025", "2026", "2027",
	}
	// BgmWeekdays 是星期筛选项, 站点用 1-6 表示周一到周六, 7 表示周日.
	BgmWeekdays = map[string]int{
		"星期日": 7,
		"星期一": 1,
		"星期二": 2,
		"星期三": 3,
		"星期四": 4,
		"星期五": 5,
		"星期六": 6,
	}
)

// BgmQuery 是番组索引的查询条件, 零值表示不限.
type BgmQuery struct {
	Month   int
	Year    string
	Types   string
	Weekday int
	Page    int
}

// BgmIndex 拉取一页番组.
func (c *Client) BgmIndex(ctx context.Context, query BgmQuery) (*model.BgmPage, error) {
	page := query.Page
	if page <= 0 {
		page = 1
	}
	params := buildQuery(
		"page", page,
		"month", query.Month,
		"year", query.Year,
		"types", query.Types,
		"week", query.Weekday,
	)
	raw, err := c.Get(ctx, c.SiteURL(PathBgmIndex), params, DesktopUA())
	if err != nil {
		return nil, err
	}
	text := string(raw)
	items := ParseBgmHTML(c.BaseURL, text)
	return &model.BgmPage{
		Total:   totalCount(text),
		Page:    page,
		HasMore: len(items) >= 50,
		Items:   items,
	}, nil
}

// ParseBgmHTML 解析番组索引页面.
//
// 桌面模板的条目在 div.list > div.item, 移动模板在 div.loop_content > div.item,
// 两套模板字段含义一致, 这里统一解析.
func ParseBgmHTML(baseURL, raw string) []model.Video {
	document, err := parseDocument(raw)
	if err != nil {
		return nil
	}
	items := []model.Video{}
	seen := map[string]bool{}
	document.Find(".loop_content .item, .list .item").Each(func(_ int, node *goquery.Selection) {
		hid := ""
		node.Find("a").EachWithBreak(func(_ int, link *goquery.Selection) bool {
			href, _ := link.Attr("href")
			if value := hrefHID(href); value != "" {
				hid = value
				return false
			}
			return true
		})
		if hid == "" || seen[hid] {
			return
		}
		seen[hid] = true
		cover := coverFromImage(node.Find("img").First())
		if cover == "" {
			style, _ := node.Find("a").First().Attr("style")
			cover = absoluteURL(baseURL, backgroundURL(style))
		}
		state := cleanSpace(node.Find(".c span").First().Text())
		if state == "" {
			state = cleanSpace(node.Find(".b span").First().Text())
		}
		items = append(items, model.Video{
			HID:       hid,
			Title:     cleanSpace(node.Find(".t").First().Text()),
			Cover:     absoluteURL(baseURL, cover),
			SiteURL:   PlayURL(baseURL, hid),
			PlayCount: firstCount(node.Find(".i").First().Text()),
			State:     state,
			Tags:      cleanSpace(node.Find("b").First().Text()),
		})
	})
	return items
}

// 档案列表每页固定返回的条数.
const articlePageSize = 20

// ArticleCategories 是档案的分类筛选项.
var ArticleCategories = []string{"情报", "公告", "年鉴", "anime", "动漫"}

// ArticleList 拉取一页档案列表.
//
// 站点 /data/ 是番组档案与资讯列表, 没有 json 接口, 只能抓页面;
// 分页地址形如 /data/index_2.html, keyword 为空表示不按分类筛选.
func (c *Client) ArticleList(ctx context.Context, page int, keyword string) (*model.ArticlePage, error) {
	if page <= 0 {
		page = 1
	}
	path := "data/"
	if page > 1 {
		path = "data/index_" + itoa(page) + ".html"
	}
	raw, err := c.Get(ctx, c.SiteURL(path), buildQuery("keywords", keyword), DesktopUA())
	if err != nil {
		return nil, err
	}
	return ParseArticleHTML(c.BaseURL, string(raw), page), nil
}

// ParseArticleHTML 解析档案列表页面.
//
// 每条是 div.item, 左侧 div.l 是封面, 右侧 div.r 依次是分类 div.c,
// 标题 div.t, 播放信息 div.tt 与摘要 div.d.
func ParseArticleHTML(baseURL, raw string, page int) *model.ArticlePage {
	result := &model.ArticlePage{Page: page, Items: []model.ArticleSummary{}}
	document, err := parseDocument(raw)
	if err != nil {
		return result
	}
	seen := map[string]bool{}
	document.Find(".item").Each(func(_ int, item *goquery.Selection) {
		link := item.Find(".t a").First()
		if link.Length() == 0 {
			return
		}
		href, _ := link.Attr("href")
		hid := hrefArticleHID(href)
		if hid == "" || seen[hid] {
			return
		}
		seen[hid] = true
		cover, _ := item.Find(".l img").First().Attr("src")
		result.Items = append(result.Items, model.ArticleSummary{
			HID:      hid,
			Title:    cleanSpace(link.Text()),
			Category: cleanSpace(item.Find(".c").First().Text()),
			Cover:    absoluteURL(baseURL, cover),
			Summary:  cleanSpace(item.Find(".d").First().Text()),
			Info:     cleanSpace(item.Find(".tt").First().Text()),
			SiteURL:  ArticlePlayURL(baseURL, hid),
		})
	})
	text := document.Text()
	result.Total = totalCount(text)
	next := "index_" + itoa(page+1) + ".html"
	hasNext := false
	document.Find("a").EachWithBreak(func(_ int, link *goquery.Selection) bool {
		href, _ := link.Attr("href")
		if contains(href, next) {
			hasNext = true
			return false
		}
		return true
	})
	result.HasMore = hasNext || len(result.Items) >= articlePageSize
	return result
}

// ArticleDetail 拉取档案详情.
func (c *Client) ArticleDetail(ctx context.Context, hid string) (*model.ArticleDetail, error) {
	raw, err := c.Get(ctx, c.SiteURL(ArticlePlayPath(hid)), nil, DesktopUA())
	if err != nil {
		return nil, err
	}
	return ParseArticleDetailHTML(c.BaseURL, string(raw), hid), nil
}

// ParseArticleDetailHTML 解析档案详情页面.
//
// 档案详情沿用播放页模板, 正文固定在 .show_content 里, 里面混排文字与图片.
func ParseArticleDetailHTML(baseURL, raw, hid string) *model.ArticleDetail {
	detail := &model.ArticleDetail{HID: hid, Blocks: []model.ArticleBlock{}, CommentTypeID: articleCommentTypeID(raw)}
	document, err := parseDocument(raw)
	if err != nil {
		return detail
	}
	title := cleanSpace(document.Find("h1.show_title").First().Text())
	if title == "" {
		title = cleanSpace(document.Find("h1").First().Text())
	}
	detail.Title = title
	detail.SiteURL = ArticlePlayURL(baseURL, hid)
	if cover, ok := document.Find(`meta[property="og:image"]`).First().Attr("content"); ok {
		detail.Cover = absoluteURL(baseURL, cover)
	}
	category, published := parseArticleHeader(cleanSpace(document.Find(".show_top .l .t").First().Text()))
	detail.Category = category
	detail.Published = published

	content := articleContent(document)
	if content != nil {
		blocks, tags := articleBlocks(baseURL, content)
		detail.Blocks = blocks
		detail.Tags = tags
	}
	return detail
}

// articleContent 取正文容器.
//
// 档案页固定用 .show_content, 老页面没有这个类时, 取嵌套不深且文字最多的 div.
func articleContent(document *goquery.Document) *goquery.Selection {
	if explicit := document.Find(".show_content").First(); explicit.Length() > 0 {
		return explicit
	}
	var (
		best       *goquery.Selection
		bestLength int
	)
	document.Find("div").Each(func(_ int, node *goquery.Selection) {
		if node.Find("div").Length() > 6 {
			return
		}
		if length := len(cleanSpace(node.Text())); length > bestLength {
			best = node
			bestLength = length
		}
	})
	return best
}

// articleBlocks 把正文拆成段落与图片, 并收集形如 #忍空 的标签.
func articleBlocks(baseURL string, content *goquery.Selection) ([]model.ArticleBlock, []string) {
	blocks := []model.ArticleBlock{}
	tags := []string{}
	content.Contents().Each(func(_ int, node *goquery.Selection) {
		if goquery.NodeName(node) == "#text" {
			if text := cleanSpace(node.Text()); text != "" {
				blocks = append(blocks, model.ArticleBlock{Type: "text", Text: text})
			}
			return
		}
		if goquery.NodeName(node) == "img" {
			if src, ok := node.Attr("src"); ok && src != "" {
				blocks = append(blocks, model.ArticleBlock{Type: "image", Image: absoluteURL(baseURL, src)})
			}
			return
		}
		text := cleanSpace(node.Text())
		if text != "" {
			if isTagLine(text) {
				tags = append(tags, splitTags(text)...)
			} else {
				blocks = append(blocks, model.ArticleBlock{Type: "text", Text: text})
			}
		}
		node.Find("img").Each(func(_ int, image *goquery.Selection) {
			if src, ok := image.Attr("src"); ok && src != "" {
				blocks = append(blocks, model.ArticleBlock{Type: "image", Image: absoluteURL(baseURL, src)})
			}
		})
	})
	if len(blocks) == 0 {
		if text := cleanSpace(content.Text()); text != "" {
			blocks = append(blocks, model.ArticleBlock{Type: "text", Text: text})
		}
	}
	return blocks, tags
}

// parseArticleHeader 解析面包屑, 形如 档案 / 情报 / 2026-10-11 20:21:12.
func parseArticleHeader(text string) (category, published string) {
	parts := []string{}
	for _, part := range splitAndTrim(text, "/") {
		if part != "" {
			parts = append(parts, part)
		}
	}
	if len(parts) < 2 {
		return "", ""
	}
	last := parts[len(parts)-1]
	if isDateText(last) {
		return parts[len(parts)-2], last
	}
	return last, ""
}

// articleCommentTypeID 从页面里的 commentid=content_41-... 取分区 id.
func articleCommentTypeID(raw string) int {
	match := articleCommentPattern.FindStringSubmatch(raw)
	if match == nil {
		return 0
	}
	value, err := strconv.Atoi(match[1])
	if err != nil {
		return 0
	}
	return value
}

// totalCount 取页面上的 共N条 文案.
func totalCount(raw string) int {
	match := totalCountPattern.FindStringSubmatch(raw)
	if match == nil {
		return 0
	}
	value, err := strconv.Atoi(match[1])
	if err != nil {
		return 0
	}
	return value
}
