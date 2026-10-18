package model

// RankGroup 是一个分组下的榜单.
//
// 站点把排行榜按 今天 / 本周 / 本月 / 今年 分成几组,
// 在线榜这类页面只有一个分组, 此时 Period 为 -1.
type RankGroup struct {
	Title string `json:"title" yaml:"title"`
	// Period: 0 今天, 1 本周, 2 本月, 3 今年, -1 表示不是时间分组.
	Period int     `json:"period" yaml:"period"`
	Items  []Video `json:"items" yaml:"items"`
}

// HotKeyword 是热搜榜里的一个关键词.
type HotKeyword struct {
	Rank    int    `json:"rank" yaml:"rank"`
	Keyword string `json:"keyword" yaml:"keyword"`
	// Count 是搜索次数.
	Count int `json:"count" yaml:"count"`
}

// HotSearchGroup 是热搜榜的一个时间分组.
type HotSearchGroup struct {
	Title string       `json:"title" yaml:"title"`
	Items []HotKeyword `json:"items" yaml:"items"`
}

// UserRankItem 是 u 榜里的一个用户条目.
type UserRankItem struct {
	UserID   int    `json:"user_id" yaml:"user_id"`
	UserName string `json:"user_name" yaml:"user_name"`
	Rank     int    `json:"rank" yaml:"rank"`
	Avatar   string `json:"avatar,omitempty" yaml:"avatar,omitempty"`
	// Badge 是用户身上的标签, 例如 1元9次.
	Badge string `json:"badge,omitempty" yaml:"badge,omitempty"`
}

// UserRankGroup 是 u 榜的一个分组.
type UserRankGroup struct {
	Title string         `json:"title" yaml:"title"`
	Items []UserRankItem `json:"items" yaml:"items"`
}

// WeekGroup 是首页新番时间表的一个分组.
type WeekGroup struct {
	Title string  `json:"title" yaml:"title"`
	Items []Video `json:"items" yaml:"items"`
}

// WeekBgmGroup 是本周新番的一个日期分组.
type WeekBgmGroup struct {
	Date    string  `json:"date" yaml:"date"`
	Weekday string  `json:"weekday" yaml:"weekday"`
	Title   string  `json:"title" yaml:"title"`
	Items   []Video `json:"items" yaml:"items"`
}

// AdItem 是首页广告位的一条广告.
type AdItem struct {
	ImageURL string `json:"image_url" yaml:"image_url"`
	LinkURL  string `json:"link_url" yaml:"link_url"`
}
