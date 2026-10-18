package model

// SpaceResult 是用户空间的一页数据.
type SpaceResult struct {
	Space Space `json:"space" yaml:"space"`
	Page  int   `json:"page" yaml:"page"`
	// HasMore 表示可能还有下一页, 站点每页固定返回 50 条.
	HasMore bool    `json:"has_more" yaml:"has_more"`
	Items   []Video `json:"items" yaml:"items"`
}
