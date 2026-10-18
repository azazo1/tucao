package model

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

// PlayPage 是播放页 html 里解析出的附加信息.
type PlayPage struct {
	Description string         `json:"description" yaml:"description"`
	Subject     []SubjectField `json:"subject,omitempty" yaml:"subject,omitempty"`
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
