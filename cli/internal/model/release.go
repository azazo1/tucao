package model

// Release 是 GitHub 上的一条发布.
type Release struct {
	// TagName 是标签名, 形如 v1.2.0.
	TagName string `json:"tag_name" yaml:"tag_name"`
	Name    string `json:"name,omitempty" yaml:"name,omitempty"`
	Body    string `json:"body,omitempty" yaml:"body,omitempty"`
	PageURL string `json:"page_url" yaml:"page_url"`
	// Prerelease 为真时是预发布版本.
	Prerelease  bool   `json:"prerelease" yaml:"prerelease"`
	PublishedAt string `json:"published_at,omitempty" yaml:"published_at,omitempty"`
}

// FormStatus 是站点表单响应的识别结果.
type FormStatus string

const (
	// FormSuccess 表示站点明确回复成功.
	FormSuccess FormStatus = "success"
	// FormRejected 表示站点明确回复失败.
	FormRejected FormStatus = "rejected"
	// FormUnknown 表示响应无法识别, 不能当成成功.
	FormUnknown FormStatus = "unknown"
)

// FormResult 是站点表单页面的解析结果.
type FormResult struct {
	Status  FormStatus `json:"status" yaml:"status"`
	Message string     `json:"message" yaml:"message"`
}

// IsSuccess 判断表单是否明确成功.
func (f FormResult) IsSuccess() bool { return f.Status == FormSuccess }
