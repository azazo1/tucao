package model

import "fmt"

// VideoPart 是视频的一个分P.
//
// 站点存在两代视频源: 自建源直接给 file 直链, 早期第三方源只有 vid,
// 需要再换一次地址, 客户端目前只支持自建源.
type VideoPart struct {
	// Index 是从 0 开始的分P序号, 与站点弹幕接口的分P编号一致.
	Index int `json:"index" yaml:"index"`
	// Number 是从 1 开始的分P序号, 便于人读.
	Number     int    `json:"number" yaml:"number"`
	Title      string `json:"title" yaml:"title"`
	File       string `json:"file,omitempty" yaml:"file,omitempty"`
	VID        string `json:"vid,omitempty" yaml:"vid,omitempty"`
	Type       string `json:"type,omitempty" yaml:"type,omitempty"`
	ThirdParty bool   `json:"third_party,omitempty" yaml:"third_party,omitempty"`
}

// Video 是视频条目, 列表页与详情页共用.
type Video struct {
	HID          string      `json:"hid" yaml:"hid"`
	Title        string      `json:"title" yaml:"title"`
	TypeID       int         `json:"typeid" yaml:"typeid"`
	TypeName     string      `json:"typename,omitempty" yaml:"typename,omitempty"`
	Cover        string      `json:"cover,omitempty" yaml:"cover,omitempty"`
	SiteURL      string      `json:"site_url,omitempty" yaml:"site_url,omitempty"`
	PlayCount    int         `json:"play_count" yaml:"play_count"`
	DanmakuCount int         `json:"danmaku_count" yaml:"danmaku_count"`
	CreateTime   int64       `json:"create_time,omitempty" yaml:"create_time,omitempty"`
	CreateAt     string      `json:"create_at,omitempty" yaml:"create_at,omitempty"`
	Description  string      `json:"description,omitempty" yaml:"description,omitempty"`
	Keywords     string      `json:"keywords,omitempty" yaml:"keywords,omitempty"`
	UserName     string      `json:"user_name,omitempty" yaml:"user_name,omitempty"`
	UserID       int         `json:"user_id,omitempty" yaml:"user_id,omitempty"`
	PartCount    int         `json:"part_count" yaml:"part_count"`
	Parts        []VideoPart `json:"parts,omitempty" yaml:"parts,omitempty"`
	// State 是页面上的集数状态, 只有时间表与番组索引这类页面会给.
	State string `json:"state,omitempty" yaml:"state,omitempty"`
	// Tags 是页面上的题材标签, 同样只有部分页面会给.
	Tags string `json:"tags,omitempty" yaml:"tags,omitempty"`
}

// VideoList 是分页的视频列表.
type VideoList struct {
	Total    int     `json:"total" yaml:"total"`
	Page     int     `json:"page" yaml:"page"`
	PageSize int     `json:"page_size" yaml:"page_size"`
	HasMore  bool    `json:"has_more" yaml:"has_more"`
	Items    []Video `json:"items" yaml:"items"`
}

// SubjectField 是番组信息的一项, 字段名不写死, 保留页面顺序.
type SubjectField struct {
	Label string `json:"label" yaml:"label"`
	Value string `json:"value" yaml:"value"`
}

// PlayPagePart 是播放页里给出的分P来源.
//
// 详情接口有时只返回半个地址, 例如 sharepoint 直链会被截断成 ...?share,
// 装上 play 页里这份地址才是播放器真正使用的, 因此以它为准.
type PlayPagePart struct {
	Type string `json:"type,omitempty" yaml:"type,omitempty"`
	File string `json:"file,omitempty" yaml:"file,omitempty"`
}

// PlayPage 是播放页 html 里解析出的附加信息.
type PlayPage struct {
	Description string         `json:"description" yaml:"description"`
	Subject     []SubjectField `json:"subject,omitempty" yaml:"subject,omitempty"`
	Parts       []PlayPagePart `json:"parts,omitempty" yaml:"parts,omitempty"`
}

// ApplyPlayParts 用播放页里的地址补全或替换分P直链.
//
// 只按顺序覆盖已有分P, 额外的条目会被忽略, 免得页面上的非分P条目变成幽灵分P;
// 详情接口一个分P都没给时, 才用播放页的条目建立分P列表.
// 标题仍取详情接口的, 播放页里没有标题.
func (v *Video) ApplyPlayParts(parts []PlayPagePart) {
	filled := make([]PlayPagePart, 0, len(parts))
	for _, part := range parts {
		if part.File != "" {
			filled = append(filled, part)
		}
	}
	if len(filled) == 0 {
		return
	}
	if len(v.Parts) == 0 {
		for index, part := range filled {
			v.Parts = append(v.Parts, VideoPart{
				Index:      index,
				Number:     index + 1,
				Title:      fmt.Sprintf("p%d", index+1),
				File:       part.File,
				Type:       part.Type,
				ThirdParty: false,
			})
		}
		if v.PartCount < len(v.Parts) {
			v.PartCount = len(v.Parts)
		}
		return
	}
	for index, part := range filled {
		if index >= len(v.Parts) {
			break
		}
		// 地址没变时不改类型, 免得把第三方的标记冲掉.
		if v.Parts[index].File == part.File {
			continue
		}
		v.Parts[index].File = part.File
		if part.Type != "" {
			v.Parts[index].Type = part.Type
		}
		v.Parts[index].ThirdParty = false
	}
}

// VideoStats 是播放页与档案页的统计, 取不到的项为空.
type VideoStats struct {
	PlayCount     *int `json:"play_count,omitempty" yaml:"play_count,omitempty"`
	OnlineCount   *int `json:"online_count,omitempty" yaml:"online_count,omitempty"`
	CommentCount  *int `json:"comment_count,omitempty" yaml:"comment_count,omitempty"`
	FavoriteCount *int `json:"favorite_count,omitempty" yaml:"favorite_count,omitempty"`
}

// VideoDetail 是视频详情命令的完整输出.
type VideoDetail struct {
	Video Video `json:"video" yaml:"video"`
	// FullDescription 是播放页里的完整简介, 详情接口只给截断的一段.
	FullDescription string         `json:"full_description,omitempty" yaml:"full_description,omitempty"`
	Subject         []SubjectField `json:"subject,omitempty" yaml:"subject,omitempty"`
	Stats           *VideoStats    `json:"stats,omitempty" yaml:"stats,omitempty"`
}
