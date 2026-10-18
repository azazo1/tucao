package api

import (
	"encoding/json"
	"strings"
	"testing"

	"github.com/azazo1/tucao/cli/internal/model"
)

func TestParseRankHTML(t *testing.T) {
	raw := readFixture(t, "rank.html")
	groups := ParseRankHTML("https://www.tucao.my/", raw)
	if len(groups) != 4 {
		t.Fatalf("排行榜应解析出 4 个时间维度, 实际 %d", len(groups))
	}
	wantTitles := []string{"今天", "本周", "本月", "今年"}
	wantPeriods := []int{0, 1, 2, 3}
	for index, group := range groups {
		if group.Title != wantTitles[index] {
			t.Fatalf("第 %d 组标题为 %q, 期望 %q", index, group.Title, wantTitles[index])
		}
		if group.Period != wantPeriods[index] {
			t.Fatalf("第 %d 组 period 为 %d, 期望 %d", index, group.Period, wantPeriods[index])
		}
		checkVideos(t, group.Items, true)
		checkUniqueHID(t, group.Items)
	}
}

func TestParseRankVariants(t *testing.T) {
	for _, name := range []string{"danmu", "digg", "fav_hot"} {
		groups := ParseRankHTML("https://www.tucao.my/", readFixture(t, "rank_"+name+".html"))
		if len(groups) != 4 {
			t.Fatalf("%s 应解析出 4 个时间维度, 实际 %d", name, len(groups))
		}
		for _, group := range groups {
			checkVideos(t, group.Items, true)
		}
	}

	zero := ParseRankHTML("https://www.tucao.my/", readFixture(t, "rank_zero.html"))
	if len(zero) == 0 {
		t.Fatal("无人区应有分组")
	}
	for _, group := range zero {
		if group.Period != -1 {
			t.Fatalf("无人区分组 %q 的 period 应为 -1, 实际 %d", group.Title, group.Period)
		}
		checkVideos(t, group.Items, true)
	}

	for _, name := range []string{"ol", "new", "pos"} {
		groups := ParseRankHTML("https://www.tucao.my/", readFixture(t, "rank_"+name+".html"))
		if len(groups) != 1 {
			t.Fatalf("%s 是单列表页面, 应整体作为一组, 实际 %d 组", name, len(groups))
		}
		if groups[0].Period != -1 {
			t.Fatalf("%s 的 period 应为 -1", name)
		}
		checkVideos(t, groups[0].Items, true)
		for _, item := range groups[0].Items {
			if !strings.Contains(item.Cover, "tucao.my") {
				t.Fatalf("%s 的封面应补成站内绝对地址: %q", name, item.Cover)
			}
		}
	}
}

func TestParseRankHTMLOnEmptyPage(t *testing.T) {
	if groups := ParseRankHTML("https://www.tucao.my/", "<html><body>空页面</body></html>"); len(groups) != 0 {
		t.Fatalf("空页面应返回空结果, 实际 %d 组", len(groups))
	}
}

func TestParseHotSearchHTML(t *testing.T) {
	groups := ParseHotSearchHTML(readFixture(t, "rank_hot_search.html"))
	if len(groups) == 0 {
		t.Fatal("热搜榜应解析出分组")
	}
	wantTitles := []string{"今天", "本周", "本月", "今年"}
	for index, group := range groups {
		if index < len(wantTitles) && group.Title != wantTitles[index] {
			t.Fatalf("第 %d 组标题为 %q, 期望 %q", index, group.Title, wantTitles[index])
		}
		if len(group.Items) == 0 {
			t.Fatalf("分组 %q 没有关键词", group.Title)
		}
		for position, item := range group.Items {
			if item.Keyword == "" || item.Count <= 0 {
				t.Fatalf("关键词条目不完整: %+v", item)
			}
			if item.Rank != position+1 {
				t.Fatalf("分组 %q 第 %d 条排名为 %d", group.Title, position, item.Rank)
			}
		}
	}
	first := groups[0].Items[0]
	if first.Count != 112 || first.Keyword != "无修" || first.Rank != 1 {
		t.Fatalf("首条热搜与样本不一致: %+v", first)
	}
}

func TestParseHotSearchKeepsNumericKeyword(t *testing.T) {
	raw := `<div class="time_item"><div class="time_title">今天</div>
	<div class="hot_search_list">
	<div class="item"><a href="/html/hot_search.html"><span>38次</span><b>6</b>1月</a></div>
	</div></div>`
	groups := ParseHotSearchHTML(raw)
	if len(groups) != 1 || len(groups[0].Items) != 1 {
		t.Fatalf("应解析出一组一条, 实际 %+v", groups)
	}
	item := groups[0].Items[0]
	if item.Rank != 6 || item.Count != 38 || item.Keyword != "1月" {
		t.Fatalf("以数字开头的关键词被并进了排名: %+v", item)
	}
}

func TestParseUserRankHTML(t *testing.T) {
	raw := readFixture(t, "rank_user_hot.html")
	// 视频榜单的解析器认不出用户链接, 结果应为空.
	if groups := ParseRankHTML("https://www.tucao.my/", raw); len(groups) != 0 {
		t.Fatalf("视频榜单解析器不应解析 u 榜, 实际 %d 组", len(groups))
	}
	groups := ParseUserRankHTML("https://www.tucao.my/", raw)
	if len(groups) == 0 {
		t.Fatal("u 榜应解析出分组")
	}
	for _, group := range groups {
		if group.Title == "" || len(group.Items) == 0 {
			t.Fatalf("分组不完整: %+v", group)
		}
		hasUser := false
		for _, item := range group.Items {
			if item.UserName == "" || item.Rank <= 0 {
				t.Fatalf("用户条目不完整: %+v", item)
			}
			if !strings.HasPrefix(item.Avatar, "http") {
				t.Fatalf("头像应补成绝对地址: %q", item.Avatar)
			}
			if item.UserID > 0 {
				hasUser = true
			}
		}
		// 站点会给出 uid 为 0 的聚合条目, 但一组里应该仍有真实用户.
		if !hasUser {
			t.Fatalf("分组 %q 没有真实用户", group.Title)
		}
	}
}

func TestParseWeekHTML(t *testing.T) {
	groups := ParseWeekHTML("https://www.tucao.my/", readFixture(t, "home_week.html"))
	if len(groups) != 9 {
		t.Fatalf("时间表应解析出 9 组, 实际 %d", len(groups))
	}
	wantTitles := []string{"周日", "周一", "周二", "周三", "周四", "周五", "周六", "剧场", "天朝"}
	for index, group := range groups {
		if group.Title != wantTitles[index] {
			t.Fatalf("第 %d 组标题为 %q, 期望 %q", index, group.Title, wantTitles[index])
		}
		if len(group.Items) == 0 {
			t.Fatalf("分组 %q 为空", group.Title)
		}
		checkVideos(t, group.Items, true)
		checkUniqueHID(t, group.Items)
	}
	if groups := ParseWeekHTML("https://www.tucao.my/", "<html><body>空页面</body></html>"); len(groups) != 0 {
		t.Fatalf("没有时间表时应返回空结果, 实际 %d 组", len(groups))
	}
}

func TestParseWeekBgmHTML(t *testing.T) {
	groups := ParseWeekBgmHTML("https://www.tucao.my/", readFixture(t, "week_bgm.html"))
	if len(groups) == 0 {
		t.Fatal("本周新番应解析出日期分组")
	}
	for _, group := range groups {
		if len(group.Date) != 10 || group.Weekday == "" {
			t.Fatalf("日期分组不完整: %+v", group)
		}
		if !strings.Contains(group.Title, group.Weekday) {
			t.Fatalf("分组标题应含星期: %+v", group)
		}
		checkUniqueHID(t, group.Items)
		for _, item := range group.Items {
			if !strings.Contains(item.Cover, "tucao.my") {
				t.Fatalf("封面应为站内地址: %q", item.Cover)
			}
		}
	}
	if groups := ParseWeekBgmHTML("https://www.tucao.my/", "<html></html>"); len(groups) != 0 {
		t.Fatalf("空页面应返回空结果, 实际 %d 组", len(groups))
	}
}

func TestParseBgmHTML(t *testing.T) {
	items := ParseBgmHTML("https://www.tucao.my/", readFixture(t, "bgm_index.html"))
	if len(items) == 0 {
		t.Fatal("番组索引应解析出条目")
	}
	withState := 0
	for _, item := range items {
		if item.HID == "" || item.Title == "" {
			t.Fatalf("番组条目不完整: %+v", item)
		}
		if !strings.Contains(item.Cover, "tucao.my") {
			t.Fatalf("封面应为站内地址: %q", item.Cover)
		}
		if item.State != "" {
			withState++
		}
	}
	if withState == 0 {
		t.Fatal("番组索引里应该有带集数状态的条目")
	}
	checkUniqueHID(t, items)
}

func TestParseArticleHTML(t *testing.T) {
	page := ParseArticleHTML("https://www.tucao.my/", readFixture(t, "article_list.html"), 1)
	if len(page.Items) == 0 {
		t.Fatal("档案列表应解析出条目")
	}
	if page.Total <= 0 || page.Page != 1 {
		t.Fatalf("分页信息不正确: total=%d page=%d", page.Total, page.Page)
	}
	for _, item := range page.Items {
		if item.HID == "" || item.Title == "" || item.Category == "" {
			t.Fatalf("档案条目不完整: %+v", item)
		}
		if !strings.HasPrefix(item.Cover, "http") {
			t.Fatalf("封面应为绝对地址: %q", item.Cover)
		}
	}
	empty := ParseArticleHTML("https://www.tucao.my/", "<html><body>空页面</body></html>", 1)
	if len(empty.Items) != 0 || empty.Total != 0 {
		t.Fatalf("空页面应返回空结果: %+v", empty)
	}
}

func TestParseArticleDetailHTML(t *testing.T) {
	detail := ParseArticleDetailHTML("https://www.tucao.my/", readFixture(t, "article_detail.html"), "7301")
	if detail.Title == "" || !strings.HasPrefix(detail.Cover, "http") {
		t.Fatalf("档案详情头部不完整: %+v", detail)
	}
	if detail.HID != "7301" {
		t.Fatalf("档案编号错误: %s", detail.HID)
	}
	if detail.Category != "情报" {
		t.Fatalf("分类应为 情报, 实际 %q", detail.Category)
	}
	if !strings.HasPrefix(detail.Published, "2026-10-11") {
		t.Fatalf("发布时间错误: %q", detail.Published)
	}
	if detail.CommentTypeID != 41 {
		t.Fatalf("评论分区应为 41, 实际 %d", detail.CommentTypeID)
	}
	if len(detail.Blocks) == 0 {
		t.Fatal("正文段落为空")
	}
	longText := false
	archiveHeader := false
	for _, block := range detail.Blocks {
		if block.Type == "text" && len([]rune(block.Text)) > 50 {
			longText = true
		}
		if strings.Contains(block.Text, "档案 / 情报") {
			archiveHeader = true
		}
	}
	if !longText {
		t.Fatal("正文里应该有较长的段落")
	}
	if archiveHeader {
		t.Fatal("面包屑不应出现在正文里")
	}
}

func TestParseSpaceHTML(t *testing.T) {
	page := ParseSpaceHTML("https://www.tucao.my/", readFixture(t, "space.html"), 9599, 1)
	if page.Space.UserID != 9599 || page.Space.UserName == "" {
		t.Fatalf("用户信息不完整: %+v", page.Space)
	}
	if !strings.HasPrefix(page.Space.Avatar, "http") || !strings.HasPrefix(page.Space.Banner, "http") {
		t.Fatalf("头像与背景应为绝对地址: %+v", page.Space)
	}
	if page.Space.Total <= 0 {
		t.Fatalf("投稿总数应大于 0: %d", page.Space.Total)
	}
	if len(page.Items) == 0 {
		t.Fatal("用户空间应解析出投稿")
	}
	withCover := 0
	for _, item := range page.Items {
		if item.HID == "" || item.Title == "" {
			t.Fatalf("投稿条目不完整: %+v", item)
		}
		if item.Cover != "" {
			withCover++
		}
	}
	if withCover <= len(page.Items)/2 {
		t.Fatalf("多数投稿应有封面, 实际 %d/%d", withCover, len(page.Items))
	}
	checkUniqueHID(t, page.Items)

	short := ParseSpaceHTML("https://www.tucao.my/", readFixture(t, "space.html"), 9599, 2)
	_ = short
}

func TestParseInboxHTML(t *testing.T) {
	items := ParseInboxHTML("https://www.tucao.my/", readFixture(t, "message_inbox.html"))
	if len(items) != 2 {
		t.Fatalf("收件箱应解析出 2 条, 实际 %d", len(items))
	}
	first := items[0]
	if first.ID != "1001" || first.UserName != "张三" {
		t.Fatalf("首条私信与样本不一致: %+v", first)
	}
	if first.Summary != "你好, 这是第一条私信" || first.Time != "2026-10-01 10:00" {
		t.Fatalf("首条私信内容与样本不一致: %+v", first)
	}
	if len(ParseInboxHTML("https://www.tucao.my/", "<html></html>")) != 0 {
		t.Fatal("空页面应返回空结果")
	}
}

func TestParseDetailHTML(t *testing.T) {
	items := ParseDetailHTML("https://www.tucao.my/", readFixture(t, "message_detail.html"), "200")
	if len(items) != 3 {
		t.Fatalf("会话应有 3 条消息, 实际 %d", len(items))
	}
	if items[0].Content != "对方发来的消息" || items[0].Time != "2026-10-01 10:00" {
		t.Fatalf("首条消息与样本不一致: %+v", items[0])
	}
	if items[0].IsMine || !items[1].IsMine || items[2].IsMine {
		t.Fatalf("消息归属判断错误: %+v", items)
	}
	if items[0].UserID != "100" || items[1].UserID != "200" {
		t.Fatalf("发送者编号应保留: %+v", items)
	}
	for _, item := range ParseDetailHTML("https://www.tucao.my/", readFixture(t, "message_detail.html"), "") {
		if item.IsMine {
			t.Fatal("未登录时所有消息都不算自己的")
		}
	}
}

func TestParseDanmakuXML(t *testing.T) {
	items, err := ParseDanmakuXML(readFixture(t, "danmaku_real.xml"))
	if err != nil {
		t.Fatalf("解析弹幕失败: %v", err)
	}
	if len(items) == 0 {
		t.Fatal("弹幕样本应解析出条目")
	}
	first := items[0]
	if first.Time != 334.1 || first.Mode != 1 || first.Color != 16777215 {
		t.Fatalf("首条弹幕属性不符: %+v", first)
	}
	if !strings.Contains(first.Text, "乙女游戏") {
		t.Fatalf("首条弹幕内容不符: %q", first.Text)
	}
	for _, item := range items {
		if item.Text == "" || item.Position == "" {
			t.Fatalf("弹幕条目不完整: %+v", item)
		}
	}
	if empty, err := ParseDanmakuXML(""); err != nil || len(empty) != 0 {
		t.Fatalf("空响应应返回空列表: %v %d", err, len(empty))
	}
	if _, err := ParseDanmakuXML("不是 xml"); err == nil {
		t.Fatal("非法内容应当报错")
	}
}

func TestDanmakuPosition(t *testing.T) {
	cases := map[int]string{1: "scroll", 2: "scroll", 4: "bottom", 5: "top", 7: "scroll"}
	for mode, want := range cases {
		if got := DanmakuPosition(mode); got != want {
			t.Fatalf("模式 %d 的位置为 %q, 期望 %q", mode, got, want)
		}
	}
}

func TestParseReplyPayload(t *testing.T) {
	items, total, title, err := parseReplyPayload([]byte(readFixture(t, "reply_real.json")))
	if err != nil {
		t.Fatalf("解析评论失败: %v", err)
	}
	if len(items) != 2 {
		t.Fatalf("评论应有 2 条, 实际 %d", len(items))
	}
	if total != 3 {
		t.Fatalf("评论总数为 %d, 期望 3", total)
	}
	if title == "" {
		t.Fatal("评论标题不应为空")
	}
	first := items[0].toModel()
	if first.ID != "316510" || first.UserID != 453580 || first.UserName != "樱影菊忌" {
		t.Fatalf("首条评论与样本不一致: %+v", first)
	}
	if !strings.Contains(first.Content, "文库") {
		t.Fatalf("首条评论内容不符: %q", first.Content)
	}
	if first.CreateAt != "2026-10-05 12:25:05" {
		t.Fatalf("首条评论时间不符: %q", first.CreateAt)
	}
	if !strings.HasPrefix(first.Avatar, "http") {
		t.Fatalf("头像应为绝对地址: %q", first.Avatar)
	}
}

func TestParseReplyPayloadOnEmptyResponse(t *testing.T) {
	for _, raw := range []string{"", "0", "   "} {
		items, total, _, err := parseReplyPayload([]byte(raw))
		if err != nil || len(items) != 0 || total != 0 {
			t.Fatalf("空响应应返回空列表: raw=%q err=%v items=%d", raw, err, len(items))
		}
	}
}

func TestParseVideoFixture(t *testing.T) {
	raw := []byte(readFixture(t, "view.json"))
	item, err := parseSingle(raw, parseRawVideo)
	if err != nil {
		t.Fatalf("解析视频详情失败: %v", err)
	}
	video := item.toModel("https://www.tucao.my/")
	if video.HID != "4107869" {
		t.Fatalf("视频编号为 %q", video.HID)
	}
	if video.Title == "" || video.UserName == "" || video.UserID <= 0 {
		t.Fatalf("详情字段不完整: %+v", video)
	}
	if len(video.Parts) != 2 {
		t.Fatalf("分P数量为 %d, 期望 2", len(video.Parts))
	}
	if video.PartCount != 2 {
		t.Fatalf("分P计数为 %d, 期望 2", video.PartCount)
	}
	for _, part := range video.Parts {
		if part.ThirdParty || !strings.HasPrefix(part.File, "http") {
			t.Fatalf("自建源分P应带直链: %+v", part)
		}
	}
	if rawValue := string(raw); !json.Valid([]byte(rawValue)) {
		t.Fatal("样本应当是合法 json")
	}
}

func TestCommentIDAndPlayerID(t *testing.T) {
	if got := CommentID(11, "4107869"); got != "content_11-4107869-1" {
		t.Fatalf("评论楼层 id 为 %q", got)
	}
	if got := CommentID(24, "123"); got != "content_24-123-1" {
		t.Fatalf("评论楼层 id 为 %q", got)
	}
	if got := PlayerID(11, "4107869", 0); got != "11-4107869-1-0" {
		t.Fatalf("播放器 id 为 %q", got)
	}
	if got := PlayerID(11, "4107869", 1); got != "11-4107869-1-1" {
		t.Fatalf("播放器 id 为 %q", got)
	}
}

func TestParseFormResponse(t *testing.T) {
	rejected := ParseFormResponse(readFixture(t, "forgot_rejected.html"))
	if rejected.Status != "rejected" {
		t.Fatalf("失败页应识别为 rejected, 实际 %q", rejected.Status)
	}
	if rejected.Message == "" {
		t.Fatal("失败页应带提示文本")
	}
	succeeded := ParseFormResponse("<html><body><div>密码重置成功</div></body></html>")
	if !succeeded.IsSuccess() {
		t.Fatalf("成功页应识别为成功, 实际 %q", succeeded.Status)
	}
	unknown := ParseFormResponse("<html><body><form><input name='a'></form></body></html>")
	if unknown.Status != "unknown" {
		t.Fatalf("带表单的页面不能当成成功, 实际 %q", unknown.Status)
	}
}

func TestParseRelease(t *testing.T) {
	payload := map[string]any{
		"tag_name":   "v1.4.0",
		"html_url":   "https://github.com/azazo1/tucao/releases/tag/v1.4.0",
		"name":       "吐槽 v1.4.0",
		"body":       "说明",
		"prerelease": false,
	}
	release := ParseRelease(payload)
	if release == nil || release.TagName != "v1.4.0" || release.PageURL == "" {
		t.Fatalf("发布解析失败: %+v", release)
	}
	if ParseRelease(map[string]any{"html_url": "https://x"}) != nil {
		t.Fatal("缺少 tag 时应返回 nil")
	}
}

// checkVideos 校验视频列表的基本完整性.
func checkVideos(t *testing.T, items []model.Video, needCover bool) {
	t.Helper()
	if len(items) == 0 {
		t.Fatal("列表为空")
	}
	for _, item := range items {
		if item.HID == "" || item.Title == "" {
			t.Fatalf("条目不完整: %+v", item)
		}
		if needCover && !strings.HasPrefix(item.Cover, "http") {
			t.Fatalf("封面应为绝对地址: %q", item.Cover)
		}
	}
}

func checkUniqueHID(t *testing.T, items []model.Video) {
	t.Helper()
	seen := map[string]bool{}
	for _, item := range items {
		if item.HID == "" {
			continue
		}
		if seen[item.HID] {
			t.Fatalf("同一列表内出现重复条目: %s", item.HID)
		}
		seen[item.HID] = true
	}
}
