package api

import (
	"net/url"
	"regexp"
	"strconv"
	"strings"
	"unicode/utf8"

	"github.com/PuerkitoBio/goquery"
	"golang.org/x/net/html"
	"golang.org/x/net/html/atom"
)

var (
	// css 里的 url(...) 取值.
	backgroundPattern = regexp.MustCompile(`url\(([^)]+)\)`)
	// 播放页地址里的 hid.
	playHrefPattern = regexp.MustCompile(`/play/h?(\d+)/`)
	// 档案页地址里的编号, 形如 /play/d7301/ 与旧版 /play/7300/.
	articleHrefPattern = regexp.MustCompile(`/play/[du]?(\d+)/`)
	// 用户空间地址里的 uid.
	userHrefPattern = regexp.MustCompile(`/play/u(\d+)/`)
	// 播放数等数字, 允许千分位与一位小数.
	countPattern = regexp.MustCompile(`([\d,]+(?:\.\d+)?)`)
	// html 实体, 用于判断是否还需要再解一层.
	entityPattern = regexp.MustCompile(`&(?:#\d+|#x[0-9a-fA-F]+|[a-zA-Z][a-zA-Z0-9]+);`)
	// 档案详情页里的评论楼层分区 id.
	articleCommentPattern = regexp.MustCompile(`commentid=content_(\d+)-`)
	// 页面上的总条数, 形如 共5568条.
	totalCountPattern = regexp.MustCompile(`共(\d+)条`)
	// 正文里的纯标签行.
	tagLinePattern = regexp.MustCompile(`^(#[^\s#]+)+$`)
	// 日期文本.
	dateTextPattern = regexp.MustCompile(`\d{4}-\d{2}-\d{2}`)
	// 私信会话编号.
	messageIDPattern = regexp.MustCompile(`messageid=(\d+)`)
)

// formValues 把字符串表转成表单参数.
func formValues(values map[string]string) url.Values {
	form := url.Values{}
	for key, value := range values {
		form.Set(key, value)
	}
	return form
}

// parseDocument 解析 html 页面.
func parseDocument(raw string) (*goquery.Document, error) {
	document, err := goquery.NewDocumentFromReader(strings.NewReader(raw))
	if err != nil {
		return nil, WrapError(CodeUpstream, "解析页面", "页面内容无法解析", err)
	}
	return document, nil
}

// backgroundURL 从 style 属性里取出 background-image 地址.
func backgroundURL(style string) string {
	match := backgroundPattern.FindStringSubmatch(style)
	if match == nil {
		return ""
	}
	return strings.Trim(strings.TrimSpace(match[1]), `"'`)
}

// firstCount 取出文本里的第一个数字.
//
// 支持千分位与一位小数, 并识别站点常用的 万 与 亿 后缀,
// 例如 44,489次播放 与 1.2万次播放.
func firstCount(text string) int {
	location := countPattern.FindStringSubmatchIndex(text)
	if location == nil {
		return 0
	}
	numberText := strings.ReplaceAll(text[location[2]:location[3]], ",", "")
	value, err := strconv.ParseFloat(numberText, 64)
	if err != nil {
		return 0
	}
	switch suffixOf(text[location[3]:]) {
	case "万":
		value *= 10000
	case "亿":
		value *= 100000000
	}
	return int(value)
}

// suffixOf 取文本的第一个字符, 空串返回空串.
func suffixOf(text string) string {
	if text == "" {
		return ""
	}
	symbol, _ := utf8.DecodeRuneInString(text)
	return string(symbol)
}

// absoluteURL 把站内相对地址补成绝对地址.
func absoluteURL(baseURL, raw string) string {
	text := strings.TrimSpace(raw)
	if text == "" || strings.HasPrefix(text, "http://") || strings.HasPrefix(text, "https://") {
		return text
	}
	return strings.TrimSuffix(baseURL, "/") + "/" + strings.TrimPrefix(text, "/")
}

// decodeHTMLText 把站点返回的富文本还原成纯文本.
//
// 简介等字段里会直接带 &mdash; 这类实体, 偶尔还有 <br>;
// 个别字段被二次转义 (例如 &amp;acute;), 解析一次后仍残留实体时再补一层.
func decodeHTMLText(raw string) string {
	if raw == "" {
		return raw
	}
	text := htmlFragmentText(strings.ReplaceAll(strings.ReplaceAll(raw, "<br>", "\n"), "<br/>", "\n"))
	if !entityPattern.MatchString(text) {
		return text
	}
	return htmlFragmentText(text)
}

// htmlFragmentText 取出 html 片段的纯文本, br 转成换行.
//
// 上下文节点必须同时给出 Data 与 DataAtom, 否则 html 包会判定节点不一致.
func htmlFragmentText(raw string) string {
	nodes, err := html.ParseFragment(strings.NewReader(raw), &html.Node{
		Type:     html.ElementNode,
		Data:     atom.Div.String(),
		DataAtom: atom.Div,
	})
	if err != nil {
		return raw
	}
	var builder strings.Builder
	for _, node := range nodes {
		builder.WriteString(nodeText(node))
	}
	return builder.String()
}

// nodeText 收集节点下的全部文本, br 转成换行.
func nodeText(node *html.Node) string {
	var builder strings.Builder
	var walk func(*html.Node)
	walk = func(current *html.Node) {
		switch current.Type {
		case html.TextNode:
			builder.WriteString(current.Data)
			return
		case html.ElementNode:
			if current.Data == "br" {
				builder.WriteString("\n")
				return
			}
		}
		for child := current.FirstChild; child != nil; child = child.NextSibling {
			walk(child)
		}
	}
	walk(node)
	return builder.String()
}

// cleanSpace 合并连续空白并去掉首尾空白.
func cleanSpace(raw string) string {
	return strings.Join(strings.Fields(raw), " ")
}

// contains 判断文本里是否出现子串, 便于在闭包里提前结束遍历.
func contains(text, sub string) bool { return strings.Contains(text, sub) }

// splitAndTrim 按分隔符切分并去掉每一项的空白.
func splitAndTrim(text, separator string) []string {
	parts := strings.Split(text, separator)
	for index := range parts {
		parts[index] = strings.TrimSpace(parts[index])
	}
	return parts
}

// isTagLine 判断正文段落是否是纯标签行, 例如 `#忍空`.
func isTagLine(text string) bool { return tagLinePattern.MatchString(text) }

// splitTags 把标签行拆成标签列表, 去掉井号.
func splitTags(text string) []string {
	tags := []string{}
	for _, part := range strings.Fields(text) {
		trimmed := strings.TrimPrefix(part, "#")
		if trimmed != "" {
			tags = append(tags, trimmed)
		}
	}
	return tags
}

// isDateText 判断文本里是否含日期, 用于识别面包屑里的发布时间.
func isDateText(text string) bool { return dateTextPattern.MatchString(text) }

// regexpReplace 用正则做一次整体替换.
func regexpReplace(text, pattern, replacement string) string {
	return regexp.MustCompile(pattern).ReplaceAllString(text, replacement)
}

// itoa 是 strconv.Itoa 的短别名, 让查询参数构造更紧凑.
func itoa(value int) string { return strconv.Itoa(value) }

// hrefHID 从播放页地址里取 hid.
func hrefHID(href string) string {
	match := playHrefPattern.FindStringSubmatch(href)
	if match == nil {
		return ""
	}
	return match[1]
}

// hrefArticleHID 从档案地址里取编号.
func hrefArticleHID(href string) string {
	match := articleHrefPattern.FindStringSubmatch(href)
	if match == nil {
		return ""
	}
	return match[1]
}

// hrefUID 从用户空间地址里取 uid.
func hrefUID(href string) int {
	match := userHrefPattern.FindStringSubmatch(href)
	if match == nil {
		return 0
	}
	value, err := strconv.Atoi(match[1])
	if err != nil {
		return 0
	}
	return value
}

// buildQuery 构造查询参数, 空值会被跳过.
func buildQuery(pairs ...any) url.Values {
	query := url.Values{}
	for index := 0; index+1 < len(pairs); index += 2 {
		key, ok := pairs[index].(string)
		if !ok || key == "" {
			continue
		}
		switch value := pairs[index+1].(type) {
		case nil:
			continue
		case string:
			if value == "" {
				continue
			}
			query.Set(key, value)
		case int:
			if value == 0 {
				continue
			}
			query.Set(key, strconv.Itoa(value))
		case bool:
			if !value {
				continue
			}
			query.Set(key, "1")
		default:
			continue
		}
	}
	return query
}
