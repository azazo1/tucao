package api

import (
	"testing"
)

// playPageWithSharepoint 是一个真实页面的最小复刻: 分P地址带 share= 查询串,
// 条目间用 |01** 分隔, 第二个 li 是播放器 id.
const playPageWithSharepoint = `<html><body>
<script>/* 播放器初始化 */</script>
<ul style="display:none;" id="player_code" mid="4079651_"><li>type=video&file=https://roiding-my.sharepoint.com/personal/tucao/_layouts/52/download.aspx?share=EbWI3DiAWbl|01**type=video&file=https://roiding-my.sharepoint.com/personal/tucao/_layouts/52/download.aspx?share=EVeYfqDYEiRP|02</li><li>10-4079651-1</li></ul>
</body></html>`

func TestParsePlayPartsSplitsShareLinks(t *testing.T) {
	document, err := parseDocument(playPageWithSharepoint)
	if err != nil {
		t.Fatalf("解析页面失败: %v", err)
	}
	parts := ParsePlayParts(document)
	if len(parts) != 2 {
		t.Fatalf("应解析出 2 个分P, 实际 %d", len(parts))
	}
	if parts[0].Type != "video" {
		t.Fatalf("类型解析错误: %q", parts[0].Type)
	}
	if parts[0].File != "https://roiding-my.sharepoint.com/personal/tucao/_layouts/52/download.aspx?share=EbWI3DiAWbl" {
		t.Fatalf("首条地址被切断: %q", parts[0].File)
	}
	if parts[1].File != "https://roiding-my.sharepoint.com/personal/tucao/_layouts/52/download.aspx?share=EVeYfqDYEiRP" {
		t.Fatalf("第二条地址被切断: %q", parts[1].File)
	}
	// 播放器 id 所在的 li 不能变成第三个分P.
	for _, part := range parts {
		if part.File == "10-4079651-1" {
			t.Fatal("播放器 id 被当成了分P地址")
		}
	}
}

func TestParsePlayPartsWithoutSeparatorNumbers(t *testing.T) {
	// 有些视频的条目之间没有序号, 只是 |**.
	raw := `<ul id="player_code"><li>type=video&file=https://a.example/1.mp4|**type=video&file=https://a.example/2.mp4|</li><li>24-1-1</li></ul>`
	document, err := parseDocument(raw)
	if err != nil {
		t.Fatalf("解析页面失败: %v", err)
	}
	parts := ParsePlayParts(document)
	if len(parts) != 2 {
		t.Fatalf("应解析出 2 个分P, 实际 %d", len(parts))
	}
	if parts[0].File != "https://a.example/1.mp4" || parts[1].File != "https://a.example/2.mp4" {
		t.Fatalf("地址解析错误: %+v", parts)
	}
}

func TestParsePlayPartsKeepsTitleOutOfFile(t *testing.T) {
	raw := `<ul id="player_code"><li>type=video&file=https://a.example/1.mp4&title=第一话</li></ul>`
	document, err := parseDocument(raw)
	if err != nil {
		t.Fatalf("解析页面失败: %v", err)
	}
	parts := ParsePlayParts(document)
	if len(parts) != 1 || parts[0].File != "https://a.example/1.mp4" {
		t.Fatalf("title 混进了地址: %+v", parts)
	}
}

func TestParsePlayPartsOnPageWithoutPlayerCode(t *testing.T) {
	document, err := parseDocument("<html><body>没有播放器</body></html>")
	if err != nil {
		t.Fatalf("解析页面失败: %v", err)
	}
	if parts := ParsePlayParts(document); len(parts) != 0 {
		t.Fatalf("没有 player_code 时应返回空, 实际 %+v", parts)
	}
}
