package model

// BgmPage 是番组索引的一页.
type BgmPage struct {
	Total   int     `json:"total" yaml:"total"`
	Page    int     `json:"page" yaml:"page"`
	HasMore bool    `json:"has_more" yaml:"has_more"`
	Items   []Video `json:"items" yaml:"items"`
}

// ArticleSummary 是档案列表里的一条资讯.
type ArticleSummary struct {
	// HID 是站内编号, 档案条目本身也是可播放的页面.
	HID      string `json:"hid" yaml:"hid"`
	Title    string `json:"title" yaml:"title"`
	Category string `json:"category,omitempty" yaml:"category,omitempty"`
	Cover    string `json:"cover,omitempty" yaml:"cover,omitempty"`
	Summary  string `json:"summary,omitempty" yaml:"summary,omitempty"`
	// Info 是页面上拼好的播放数与日期文案.
	Info    string `json:"info,omitempty" yaml:"info,omitempty"`
	SiteURL string `json:"site_url,omitempty" yaml:"site_url,omitempty"`
}

// ArticlePage 是档案列表的一页.
type ArticlePage struct {
	Total   int              `json:"total" yaml:"total"`
	Page    int              `json:"page" yaml:"page"`
	HasMore bool             `json:"has_more" yaml:"has_more"`
	Items   []ArticleSummary `json:"items" yaml:"items"`
}

// ArticleBlock 是档案正文里的一段, 可能是文字也可能是图片.
type ArticleBlock struct {
	// Type 取值 text 或 image.
	Type  string `json:"type" yaml:"type"`
	Text  string `json:"text,omitempty" yaml:"text,omitempty"`
	Image string `json:"image,omitempty" yaml:"image,omitempty"`
}

// ArticleDetail 是档案详情.
type ArticleDetail struct {
	HID       string `json:"hid" yaml:"hid"`
	Title     string `json:"title" yaml:"title"`
	Category  string `json:"category,omitempty" yaml:"category,omitempty"`
	Cover     string `json:"cover,omitempty" yaml:"cover,omitempty"`
	SiteURL   string `json:"site_url,omitempty" yaml:"site_url,omitempty"`
	Published string `json:"published_at,omitempty" yaml:"published_at,omitempty"`
	// CommentTypeID 是评论楼层里的分区 id, 取不到时为 0.
	CommentTypeID int            `json:"comment_type_id,omitempty" yaml:"comment_type_id,omitempty"`
	Tags          []string       `json:"tags,omitempty" yaml:"tags,omitempty"`
	Blocks        []ArticleBlock `json:"blocks" yaml:"blocks"`
}
