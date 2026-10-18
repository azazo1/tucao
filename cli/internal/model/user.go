package model

// User 是站点账号信息.
type User struct {
	UserID    int    `json:"user_id" yaml:"user_id"`
	UserName  string `json:"user_name" yaml:"user_name"`
	Nickname  string `json:"nickname,omitempty" yaml:"nickname,omitempty"`
	Avatar    string `json:"avatar,omitempty" yaml:"avatar,omitempty"`
	GroupName string `json:"group_name,omitempty" yaml:"group_name,omitempty"`
	Credit    int    `json:"credit,omitempty" yaml:"credit,omitempty"`
}

// DisplayName 优先返回昵称, 没有昵称时返回用户名.
func (u User) DisplayName() string {
	if u.Nickname != "" {
		return u.Nickname
	}
	return u.UserName
}

// Space 是用户空间页的头部信息.
type Space struct {
	UserID   int    `json:"user_id" yaml:"user_id"`
	UserName string `json:"user_name" yaml:"user_name"`
	Avatar   string `json:"avatar,omitempty" yaml:"avatar,omitempty"`
	Banner   string `json:"banner,omitempty" yaml:"banner,omitempty"`
	Sign     string `json:"sign,omitempty" yaml:"sign,omitempty"`
	Meta     string `json:"meta,omitempty" yaml:"meta,omitempty"`
	Total    int    `json:"total" yaml:"total"`
}
