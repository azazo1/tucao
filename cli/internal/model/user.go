package model

// User 是站点账号信息.
type User struct {
	UserID    int    `json:"userid" yaml:"userid"`
	UserName  string `json:"username" yaml:"username"`
	Nickname  string `json:"nickname,omitempty" yaml:"nickname,omitempty"`
	Avatar    string `json:"avatar,omitempty" yaml:"avatar,omitempty"`
	GroupName string `json:"groupname,omitempty" yaml:"groupname,omitempty"`
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
	UserID   int    `json:"userid" yaml:"userid"`
	UserName string `json:"username" yaml:"username"`
	Avatar   string `json:"avatar,omitempty" yaml:"avatar,omitempty"`
	Banner   string `json:"banner,omitempty" yaml:"banner,omitempty"`
	Sign     string `json:"sign,omitempty" yaml:"sign,omitempty"`
	Meta     string `json:"meta,omitempty" yaml:"meta,omitempty"`
	Total    int    `json:"total" yaml:"total"`
}
