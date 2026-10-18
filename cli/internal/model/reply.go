package model

// Reply 是站点评论.
type Reply struct {
	ID     string `json:"id" yaml:"id"`
	UserID int    `json:"user_id" yaml:"user_id"`
	// UserName 优先取昵称, 没有昵称时退回用户名.
	UserName string `json:"user_name,omitempty" yaml:"user_name,omitempty"`
	Content  string `json:"content" yaml:"content"`
	Avatar   string `json:"avatar,omitempty" yaml:"avatar,omitempty"`
	// CreateAt 是站点给出的时间文案, 不重新格式化.
	CreateAt string `json:"create_at,omitempty" yaml:"create_at,omitempty"`
	Support  int    `json:"support" yaml:"support"`
	// ReplyCount 是子评论数量.
	ReplyCount int `json:"reply_count" yaml:"reply_count"`
	// ReplyID 不为 0 时表示这是楼中楼回复.
	ReplyID       int     `json:"reply_id,omitempty" yaml:"reply_id,omitempty"`
	ReplyUserID   int     `json:"reply_user_id,omitempty" yaml:"reply_user_id,omitempty"`
	ReplyUserName string  `json:"reply_user_name,omitempty" yaml:"reply_user_name,omitempty"`
	Replies       []Reply `json:"replies,omitempty" yaml:"replies,omitempty"`
}

// IsRoot 判断是否是一级评论.
func (r Reply) IsRoot() bool { return r.ReplyID == 0 }

// ReplyThread 是一页评论.
type ReplyThread struct {
	Total    int     `json:"total" yaml:"total"`
	Page     int     `json:"page" yaml:"page"`
	PageSize int     `json:"page_size" yaml:"page_size"`
	Title    string  `json:"title,omitempty" yaml:"title,omitempty"`
	Items    []Reply `json:"items" yaml:"items"`
}
