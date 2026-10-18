package api

import (
	"context"
	"encoding/json"
	"strings"
	"time"

	"github.com/PuerkitoBio/goquery"
	"golang.org/x/net/html"

	"github.com/azazo1/tucao/cli/internal/model"
)

// 列表排序方式, 与站点接口的 order 参数一致.
const (
	OrderDate    = "date"
	OrderDanmaku = "mukio"
	OrderViews   = "views"
)

// rawVideo 是列表与详情接口返回的视频结构.
type rawVideo struct {
	HID         FlexString `json:"hid"`
	Title       FlexString `json:"title"`
	TypeID      FlexInt    `json:"typeid"`
	TypeName    FlexString `json:"typename"`
	Thumb       FlexString `json:"thumb"`
	Play        FlexInt    `json:"play"`
	Mukio       FlexInt    `json:"mukio"`
	Create      FlexInt    `json:"create"`
	Description FlexString `json:"description"`
	Keywords    FlexString `json:"keywords"`
	User        FlexString `json:"user"`
	UserID      FlexInt    `json:"userid"`
	Part        FlexInt    `json:"part"`
	URL         FlexString `json:"url"`
	Video       []rawPart  `json:"video"`
}

// rawPart 是详情接口里的分P结构.
type rawPart struct {
	File  FlexString `json:"file"`
	VID   FlexString `json:"vid"`
	Type  FlexString `json:"type"`
	Title FlexString `json:"title"`
}

func parseRawVideo(raw json.RawMessage) (rawVideo, error) {
	var item rawVideo
	if err := json.Unmarshal(raw, &item); err != nil {
		return rawVideo{}, WrapError(CodeUpstream, "解析视频", "视频内容无法解析", err)
	}
	return item, nil
}

// toModel 把接口结构转成输出结构.
func (r rawVideo) toModel(baseURL string) model.Video {
	parts := make([]model.VideoPart, 0, len(r.Video))
	for index, part := range r.Video {
		file := part.File.String()
		parts = append(parts, model.VideoPart{
			Index:      index,
			Number:     index + 1,
			Title:      part.Title.String(),
			File:       file,
			VID:        part.VID.String(),
			Type:       part.Type.String(),
			ThirdParty: file == "",
		})
	}
	// 详情接口的 part 字段并不可靠, 有分P列表时以列表长度为准.
	partCount := len(parts)
	if partCount <= 0 {
		partCount = r.Part.Int()
	}
	if partCount <= 0 {
		partCount = 1
	}
	createTime := int64(r.Create.Int())
	video := model.Video{
		HID:          r.HID.String(),
		Title:        r.Title.String(),
		TypeID:       r.TypeID.Int(),
		TypeName:     r.TypeName.String(),
		Cover:        r.Thumb.String(),
		SiteURL:      PlayURL(baseURL, r.HID.String()),
		PlayCount:    r.Play.Int(),
		DanmakuCount: r.Mukio.Int(),
		CreateTime:   createTime,
		CreateAt:     formatUnix(createTime),
		Description:  decodeHTMLText(r.Description.String()),
		Keywords:     r.Keywords.String(),
		UserName:     r.User.String(),
		UserID:       r.UserID.Int(),
		PartCount:    partCount,
		Parts:        parts,
	}
	return video
}

// VideoList 拉取分区视频列表.
func (c *Client) VideoList(ctx context.Context, typeID, page, pageSize int, order string) (*model.VideoList, error) {
	if order == "" {
		order = OrderDate
	}
	query := buildQuery(
		"tid", typeID,
		"page", page,
		"pagesize", pageSize,
		"order", order,
		"apikey", APIKey,
	)
	raw, err := c.Get(ctx, c.APIURL(PathList), query)
	if err != nil {
		return nil, err
	}
	items, total, err := parseList(raw, parseRawVideo)
	if err != nil {
		return nil, err
	}
	return buildVideoList(c.BaseURL, items, total, page, pageSize), nil
}

// VideoSearch 关键词搜索.
func (c *Client) VideoSearch(ctx context.Context, keyword string, typeID, page, pageSize int, order string) (*model.VideoList, error) {
	if order == "" {
		order = OrderDate
	}
	query := buildQuery(
		"q", keyword,
		"tid", typeID,
		"page", page,
		"pagesize", pageSize,
		"order", order,
		"apikey", APIKey,
	)
	raw, err := c.Get(ctx, c.APIURL(PathSearch), query)
	if err != nil {
		return nil, err
	}
	items, total, err := parseList(raw, parseRawVideo)
	if err != nil {
		return nil, err
	}
	return buildVideoList(c.BaseURL, items, total, page, pageSize), nil
}

// VideoView 拉取视频详情.
func (c *Client) VideoView(ctx context.Context, hid string) (*model.Video, error) {
	query := buildQuery("hid", hid, "apikey", APIKey)
	raw, err := c.Get(ctx, c.APIURL(PathView), query)
	if err != nil {
		return nil, err
	}
	item, err := parseSingle(raw, parseRawVideo)
	if err != nil {
		return nil, err
	}
	video := item.toModel(c.BaseURL)
	if video.HID == "" {
		return nil, NewError(CodeNotFound, "获取视频详情", "站点没有返回该视频")
	}
	return &video, nil
}

// PlayPage 抓取播放页, 同时解析完整简介与番组信息.
//
// 详情接口的 description 只返回截断的一段, 播放页的 .show_content
// 才是完整正文, 同一页面的 .vdata_info .b 里还有番组信息,
// 因此一次请求拿回两样.
func (c *Client) PlayPage(ctx context.Context, hid string) (*model.PlayPage, error) {
	raw, err := c.Get(ctx, c.SiteURL(PlayPath(hid)), nil, DesktopUA())
	if err != nil {
		return nil, err
	}
	document, err := parseDocument(string(raw))
	if err != nil {
		return nil, err
	}
	return &model.PlayPage{
		Description: ParsePlayDescription(document),
		Subject:     ParseSubjectFields(document),
	}, nil
}

// ParsePlayDescription 解析播放页里的简介正文, 去掉页面自带的标签行.
func ParsePlayDescription(document *goquery.Document) string {
	node := document.Find(".show_content").First()
	if node.Length() == 0 {
		return ""
	}
	selection := node.Clone()
	selection.Find(".show_content_n").Remove()
	inner, err := selection.Html()
	if err != nil {
		inner = selection.Text()
	}
	// 只靠 br 换行时, div 拆出来的段落会粘在一起, 这里补上分段.
	inner = regexpReplace(inner, `(?i)</p\s*>`, "\n")
	return strings.TrimSpace(decodeHTMLText(inner))
}

// ParseSubjectFields 解析播放页里的番组信息.
//
// 格式是 <span class="n">标签：</span>值<br />, 不同条目字段不完全相同,
// 因此按页面顺序保留, 不写死字段名.
func ParseSubjectFields(document *goquery.Document) []model.SubjectField {
	container := document.Find(".vdata_info .b").First()
	if container.Length() == 0 {
		return nil
	}
	fields := []model.SubjectField{}
	var (
		label  string
		buffer strings.Builder
	)
	flush := func() {
		value := cleanSpace(buffer.String())
		name := strings.Trim(label, " ")
		if name != "" && value != "" {
			fields = append(fields, model.SubjectField{Label: name, Value: value})
		}
		label = ""
		buffer.Reset()
	}
	for node := range container.Get(0).ChildNodes() {
		if node.Type == html.ElementNode {
			if node.Data == "br" {
				flush()
				continue
			}
			class := nodeAttribute(node, "class")
			if strings.Contains(" "+class+" ", " n ") {
				// 前一项的值到此结束, 这个元素本身是下一项的标签.
				flush()
				label = strings.TrimRight(cleanSpace(nodeText(node)), ":：")
				continue
			}
			buffer.WriteString(nodeText(node))
			continue
		}
		if node.Type == html.TextNode {
			buffer.WriteString(node.Data)
		}
	}
	flush()
	return fields
}

func nodeAttribute(node *html.Node, name string) string {
	for _, attribute := range node.Attr {
		if attribute.Key == name {
			return attribute.Val
		}
	}
	return ""
}

func buildVideoList(baseURL string, items []rawVideo, total, page, pageSize int) *model.VideoList {
	list := &model.VideoList{
		Total:    total,
		Page:     page,
		PageSize: pageSize,
		Items:    make([]model.Video, 0, len(items)),
	}
	for _, item := range items {
		list.Items = append(list.Items, item.toModel(baseURL))
	}
	if pageSize > 0 {
		if total > 0 {
			list.HasMore = page*pageSize < total
		} else {
			list.HasMore = len(list.Items) >= pageSize
		}
	}
	return list
}

// formatUnix 把秒级时间戳格式化成本地时间文本.
func formatUnix(seconds int64) string {
	if seconds <= 0 {
		return ""
	}
	return time.Unix(seconds, 0).Format("2006-01-02 15:04:05")
}
