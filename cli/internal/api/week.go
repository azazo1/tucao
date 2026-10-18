package api

import (
	"context"
	"time"

	"github.com/PuerkitoBio/goquery"

	"github.com/azazo1/tucao/cli/internal/model"
)

// WeekTitles 是首页新番时间表的分组顺序, 与站点标签一致.
var WeekTitles = []string{"周日", "周一", "周二", "周三", "周四", "周五", "周六", "剧场", "天朝"}

// WeekTable 拉取首页的新番时间表.
//
// 站点把九个分组一次性渲染在首页里, 由前端脚本切换显示,
// 因此这里抓首页解析, 不需要按分组分别请求.
func (c *Client) WeekTable(ctx context.Context) ([]model.WeekGroup, error) {
	raw, err := c.Get(ctx, c.SiteURL(PathHome), nil, DesktopUA())
	if err != nil {
		return nil, err
	}
	return ParseWeekHTML(c.BaseURL, string(raw)), nil
}

// HomePage 抓一次首页, 同时解析时间表与广告位.
func (c *Client) HomePage(ctx context.Context) ([]model.WeekGroup, []model.AdItem, error) {
	raw, err := c.Get(ctx, c.SiteURL(PathHome), nil, DesktopUA())
	if err != nil {
		return nil, nil, err
	}
	text := string(raw)
	return ParseWeekHTML(c.BaseURL, text), ParseHomeAds(c.BaseURL, text), nil
}

// ParseWeekHTML 解析首页里的新番时间表.
//
// 页面结构为 div.xf_list 下的九个 ul, 与 div.xf_tabs 的九个标签一一对应;
// 每个 ul 里是若干 div.item.
func ParseWeekHTML(baseURL, raw string) []model.WeekGroup {
	document, err := parseDocument(raw)
	if err != nil {
		return nil
	}
	lists := document.Find(".xf_list ul")
	if lists.Length() == 0 {
		return nil
	}
	groups := make([]model.WeekGroup, 0, lists.Length())
	lists.Each(func(index int, list *goquery.Selection) {
		title := "第 " + itoa(index+1) + " 组"
		if index < len(WeekTitles) {
			title = WeekTitles[index]
		}
		items := []model.Video{}
		seen := map[string]bool{}
		list.Find(".item").Each(func(_ int, item *goquery.Selection) {
			link := item.Find("a.t").First()
			if link.Length() == 0 {
				link = item.Find("a").First()
			}
			if link.Length() == 0 {
				return
			}
			href, _ := link.Attr("href")
			hid := hrefHID(href)
			if hid == "" || seen[hid] {
				return
			}
			seen[hid] = true
			coverNode := item.Find("a.img").First()
			if coverNode.Length() == 0 {
				coverNode = link
			}
			style, _ := coverNode.Attr("style")
			items = append(items, model.Video{
				HID:       hid,
				Title:     cleanSpace(link.Text()),
				Cover:     absoluteURL(baseURL, backgroundURL(style)),
				SiteURL:   PlayURL(baseURL, hid),
				PlayCount: firstCount(item.Find(".i span").First().Text()),
				// 集数状态与题材标签在这类页面里, 列表接口没有对应字段.
				State: cleanSpace(item.Find(".i b").First().Text()),
				Tags:  cleanSpace(item.Find("em").First().Text()),
			})
		})
		groups = append(groups, model.WeekGroup{Title: title, Items: items})
	})
	return groups
}

// Ads 拉取首页广告位里的全部广告.
func (c *Client) Ads(ctx context.Context) ([]model.AdItem, error) {
	raw, err := c.Get(ctx, c.SiteURL(PathHome), nil, DesktopUA())
	if err != nil {
		return nil, err
	}
	return ParseHomeAds(c.BaseURL, string(raw)), nil
}

// ParseHomeAds 解析首页广告位.
//
// 官方客户端的首页会把站点 header_rmb 里的多条广告图依次展示出来,
// 客户端不写死推广地址.
func ParseHomeAds(baseURL, raw string) []model.AdItem {
	document, err := parseDocument(raw)
	if err != nil {
		return nil
	}
	items := []model.AdItem{}
	seen := map[string]bool{}
	document.Find(".header_rmb a[href]").Each(func(_ int, anchor *goquery.Selection) {
		href, _ := anchor.Attr("href")
		src, _ := anchor.Find("img").First().Attr("src")
		href = cleanSpace(href)
		src = cleanSpace(src)
		if href == "" || src == "" || seen[href] {
			return
		}
		seen[href] = true
		items = append(items, model.AdItem{
			ImageURL: absoluteURL(baseURL, src),
			LinkURL:  absoluteURL(baseURL, href),
		})
	})
	return items
}

// WeekBgm 拉取本周新番.
//
// 页面按日期列出当天更新的番组, 每个 item 带 date 属性.
func (c *Client) WeekBgm(ctx context.Context) ([]model.WeekBgmGroup, error) {
	raw, err := c.Get(ctx, c.SiteURL(PathWeekBgm), nil, DesktopUA())
	if err != nil {
		return nil, err
	}
	return ParseWeekBgmHTML(c.BaseURL, string(raw)), nil
}

// ParseWeekBgmHTML 解析本周新番页面, 按 item 的 date 属性分组.
func ParseWeekBgmHTML(baseURL, raw string) []model.WeekBgmGroup {
	document, err := parseDocument(raw)
	if err != nil {
		return nil
	}
	indexByDate := map[string]int{}
	groups := []model.WeekBgmGroup{}
	document.Find(".item").Each(func(_ int, item *goquery.Selection) {
		link := item.Find("a.t").First()
		if link.Length() == 0 {
			link = item.Find("a.p").First()
		}
		if link.Length() == 0 {
			return
		}
		href, _ := link.Attr("href")
		hid := hrefHID(href)
		date, _ := item.Attr("date")
		if hid == "" || date == "" {
			return
		}
		title := cleanSpace(item.Find("a.t").First().Text())
		if title == "" {
			title = cleanSpace(link.Text())
		}
		upName := ""
		if image := item.Find("img").First(); image.Length() > 0 {
			upName, _ = image.Attr("up")
		}
		if upName == "" {
			upName = cleanSpace(item.Find(".i a").First().Text())
		}
		video := model.Video{
			HID:       hid,
			Title:     title,
			Cover:     coverFromImage(item.Find("img").First()),
			SiteURL:   PlayURL(baseURL, hid),
			UserName:  cleanSpace(upName),
			PlayCount: firstCount(item.Find(".i span").First().Text()),
		}
		if count := firstCount(item.Find(".c").First().Text()); count > video.PlayCount {
			video.PlayCount = count
		}
		if index, ok := indexByDate[date]; ok {
			for _, existing := range groups[index].Items {
				if existing.HID == hid {
					return
				}
			}
			groups[index].Items = append(groups[index].Items, video)
			return
		}
		indexByDate[date] = len(groups)
		groups = append(groups, model.WeekBgmGroup{
			Date:    date,
			Weekday: weekdayOf(date),
			Title:   weekBgmTitle(date, weekdayOf(date)),
			Items:   []model.Video{video},
		})
	})
	return groups
}

// weekBgmTitle 生成分组标题, 例如 10-12 周一.
func weekBgmTitle(date, weekday string) string {
	if len(date) >= 10 {
		return date[5:] + " " + weekday
	}
	return date + " " + weekday
}

// weekdayOf 由日期算出星期文案.
func weekdayOf(date string) string {
	parsed, err := time.Parse("2006-01-02", date)
	if err != nil {
		return ""
	}
	names := []string{"周一", "周二", "周三", "周四", "周五", "周六", "周日"}
	return names[int(parsed.Weekday()+6)%7]
}
