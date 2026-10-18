package model

// Message 是私信收件箱里的一条会话摘要.
type Message struct {
	// ID 是消息编号, 用于拉取详情与回复.
	ID string `json:"id" yaml:"id"`
	// UserName 是对方的昵称.
	UserName string `json:"user_name" yaml:"user_name"`
	Avatar   string `json:"avatar,omitempty" yaml:"avatar,omitempty"`
	Time     string `json:"time,omitempty" yaml:"time,omitempty"`
	Summary  string `json:"summary,omitempty" yaml:"summary,omitempty"`
}

// MessageDetail 是会话里的一条消息.
type MessageDetail struct {
	Content string `json:"content" yaml:"content"`
	Time    string `json:"time,omitempty" yaml:"time,omitempty"`
	// IsMine 表示这条消息是自己发出的.
	IsMine bool   `json:"is_mine" yaml:"is_mine"`
	Avatar string `json:"avatar,omitempty" yaml:"avatar,omitempty"`
	UserID string `json:"user_id,omitempty" yaml:"user_id,omitempty"`
}
