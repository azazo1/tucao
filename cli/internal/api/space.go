package api

import (
	"context"
	"strconv"
	"strings"

	"github.com/PuerkitoBio/goquery"

	"github.com/azazo1/tucao/cli/internal/model"
)

// SpacePageSize 是站点用户空间每页固定返回的条数.
const SpacePageSize = 50

// Space 拉取用户空间.
//
// 站点 play/u{uid}/ 是投稿人的主页, 没有 json 接口, 只能抓页面,
// 分页参数是 ?page=N.
func (c *Client) Space(ctx context.Context, userID, page int) (*model.SpaceResult, error) {
	if page <= 0 {
		page = 1
	}
	query := buildQuery()
	if page > 1 {
		query.Set("page", itoa(page))
	}
	raw, err := c.Get(ctx, c.SiteURL(UserPath(userID)), query, DesktopUA())
	if err != nil {
		return nil, err
	}
	return ParseSpaceHTML(c.BaseURL, string(raw), userID, page), nil
}

// ParseSpaceHTML 解析用户空间页面.
//
// 头部是 div.sheader: img.avatar 头像, img.banner 背景, h1 昵称,
// 两个 p 分别是标签与签名; 下面是 div.list 里的投稿列表.
func ParseSpaceHTML(baseURL, raw string, userID, page int) *model.SpaceResult {
	result := &model.SpaceResult{
		Space: model.Space{UserID: userID},
		Page:  page,
		Items: []model.Video{},
	}
	document, err := parseDocument(raw)
	if err != nil {
		return result
	}
	header := document.Find(".sheader").First()
	if header.Length() > 0 {
		avatar, _ := header.Find("img.avatar").First().Attr("src")
		bannerNode := header.Find("img.banner").First()
		bannerStyle, _ := bannerNode.Attr("style")
		banner := backgroundURL(bannerStyle)
		if banner == "" {
			banner, _ = bannerNode.Attr("src")
		}
		paragraphs := header.Find("p")
		meta := ""
		sign := ""
		if paragraphs.Length() > 0 {
			meta = cleanSpace(paragraphs.Eq(0).Text())
		}
		if paragraphs.Length() > 1 {
			sign = cleanSpace(paragraphs.Eq(1).Text())
		}
		result.Space = model.Space{
			UserID:   userID,
			UserName: cleanSpace(header.Find("h1").First().Text()),
			Avatar:   absoluteURL(baseURL, avatar),
			Banner:   absoluteURL(baseURL, banner),
			Sign:     sign,
			Meta:     meta,
			Total:    totalCount(cleanSpace(document.Find(".title a.m").First().Text())),
		}
	}

	seen := map[string]bool{}
	document.Find(".list .item").Each(func(_ int, item *goquery.Selection) {
		link := item.Find("a.t").First()
		if link.Length() == 0 {
			return
		}
		href, _ := link.Attr("href")
		hid := hrefHID(href)
		if hid == "" || seen[hid] {
			return
		}
		seen[hid] = true
		result.Items = append(result.Items, model.Video{
			HID:       hid,
			Title:     cleanSpace(link.Text()),
			Cover:     absoluteURL(baseURL, coverFromImage(item.Find("img").First())),
			SiteURL:   PlayURL(baseURL, hid),
			PlayCount: firstCount(item.Find(".i span").First().Text()),
			UserName:  cleanSpace(item.Find(".i a").First().Text()),
		})
	})
	// 站点分页链接不一定出现, 因此以本页是否取满作为主要依据.
	result.HasMore = len(result.Items) >= SpacePageSize
	return result
}

// MessageInbox 拉取私信收件箱, 需要登录态.
func (c *Client) MessageInbox(ctx context.Context) ([]model.Message, error) {
	path, query := IndexPath("message", "index", "inbox", nil)
	raw, err := c.Get(ctx, c.SiteURL(path), query, DesktopUA())
	if err != nil {
		return nil, err
	}
	return ParseInboxHTML(c.BaseURL, string(raw)), nil
}

// ParseInboxHTML 解析收件箱页面.
//
// 结构沿用官方客户端的解析方式: div.minbox div.item, 头像在 div.l img,
// 链接带 messageid=数字, 对方昵称在 div.u, 摘要在 div.c, 时间在 div.t.
// 昵称, 摘要与时间都相对标题链接查找, 避免 item 内还有别的同类节点时取错.
func ParseInboxHTML(baseURL, raw string) []model.Message {
	document, err := parseDocument(raw)
	if err != nil {
		return nil
	}
	items := []model.Message{}
	seen := map[string]bool{}
	document.Find("div.minbox div.item").Each(func(_ int, item *goquery.Selection) {
		link := item.Find("div.r a[href*=messageid]").First()
		href, _ := link.Attr("href")
		id := messageIDPattern.FindStringSubmatch(href)
		if id == nil || seen[id[1]] {
			return
		}
		seen[id[1]] = true
		avatar, _ := item.Find("div.l img").First().Attr("src")
		name := cleanSpace(link.Find("div.u").First().Text())
		if name == "" {
			name = cleanSpace(item.Find("div.u").First().Text())
		}
		timeText := cleanSpace(link.Find("div.t").First().Text())
		if timeText == "" {
			timeText = cleanSpace(item.Find("div.t").First().Text())
		}
		summary := cleanSpace(link.Find("div.c").First().Text())
		if summary == "" {
			summary = cleanSpace(item.Find("div.c").First().Text())
		}
		items = append(items, model.Message{
			ID:       id[1],
			UserName: name,
			Avatar:   absoluteURL(baseURL, avatar),
			Time:     timeText,
			Summary:  summary,
		})
	})
	return items
}

// MessageDetail 拉取私信会话内容.
//
// selfUID 是当前登录用户的 uid, 用来判断每条消息是否自己发出.
func (c *Client) MessageDetail(ctx context.Context, messageID, selfUID string) ([]model.MessageDetail, error) {
	path, query := IndexPath("message", "index", "read", buildQuery("messageid", messageID))
	raw, err := c.Get(ctx, c.SiteURL(path), query, DesktopUA())
	if err != nil {
		return nil, err
	}
	return ParseDetailHTML(c.BaseURL, string(raw), selfUID), nil
}

// ParseDetailHTML 解析私信会话页面.
func ParseDetailHTML(baseURL, raw, selfUID string) []model.MessageDetail {
	document, err := parseDocument(raw)
	if err != nil {
		return nil
	}
	items := []model.MessageDetail{}
	document.Find("div.mread > div.item").Each(func(_ int, item *goquery.Selection) {
		href, _ := item.Find("div.l a").First().Attr("href")
		uid := strconv.Itoa(hrefUID(href))
		if hrefUID(href) == 0 {
			uid = ""
		}
		avatar, _ := item.Find("div.l img").First().Attr("src")
		items = append(items, model.MessageDetail{
			Content: cleanSpace(item.Find("div.r div.c").First().Text()),
			Time:    cleanSpace(item.Find("div.r div.t").First().Text()),
			IsMine:  uid != "" && uid == selfUID,
			Avatar:  absoluteURL(baseURL, avatar),
			UserID:  uid,
		})
	})
	return items
}

// MessageSend 发送私信, 成功返回空串, 失败返回提示.
func (c *Client) MessageSend(ctx context.Context, toUser, subject, content string) (string, error) {
	path, query := IndexPath("message", "index", "send", nil)
	form := formValues(map[string]string{
		"info[send_to_id]": toUser,
		"info[subject]":    subject,
		"info[content]":    content,
		"dosubmit":         "1",
	})
	raw, err := c.PostForm(ctx, c.SiteURL(path), query, form)
	if err != nil {
		return "", err
	}
	return messageResult(string(raw)), nil
}

// MessageReply 回复私信, 成功返回空串, 失败返回提示.
func (c *Client) MessageReply(ctx context.Context, replyID, toUserID, subject, content string) (string, error) {
	path, query := IndexPath("message", "index", "reply", nil)
	form := formValues(map[string]string{
		"info[content]":    content,
		"info[replyid]":    replyID,
		"info[send_to_id]": toUserID,
		"info[subject]":    subject,
		"dosubmit":         "1",
	})
	raw, err := c.PostForm(ctx, c.SiteURL(path), query, form)
	if err != nil {
		return "", err
	}
	return messageResult(string(raw)), nil
}

// messageResult 站点成功时返回 1, 失败时返回提示文本.
func messageResult(raw string) string {
	text := strings.TrimSpace(stripHTMLTags(raw))
	if text == "" || text == "1" || strings.Contains(text, "成功") {
		return ""
	}
	if strings.Contains(text, "登录") || strings.Contains(text, "登陆") {
		return "请先登录后再操作"
	}
	if len(text) > 40 {
		return "操作失败"
	}
	return text
}

// stripHTMLTags 去掉 html 标签.
func stripHTMLTags(raw string) string {
	var builder strings.Builder
	inTag := false
	for _, symbol := range raw {
		switch {
		case symbol == '<':
			inTag = true
		case symbol == '>':
			inTag = false
		case !inTag:
			builder.WriteRune(symbol)
		}
	}
	return builder.String()
}
