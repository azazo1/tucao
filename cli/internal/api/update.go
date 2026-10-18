package api

import (
	"context"
	"encoding/json"
	"net/http"
	"time"

	"github.com/azazo1/tucao/cli/internal/model"
)

// GitHubLatestURL 是仓库的最新正式发布接口.
const GitHubLatestURL = "https://api.github.com/repos/azazo1/tucao/releases/latest"

// GitHubLatest 查询最新正式发布.
//
// 该接口在 api.github.com, 不需要站点 cookie, 因此使用独立客户端;
// GitHub 要求请求带上 UA, 否则直接返回 403.
func GitHubLatest(ctx context.Context) (*model.Release, error) {
	request, err := http.NewRequestWithContext(ctx, http.MethodGet, GitHubLatestURL, nil)
	if err != nil {
		return nil, WrapError(CodeInternal, "查询更新", "构造请求失败", err)
	}
	request.Header.Set("accept", "application/vnd.github+json")
	request.Header.Set("user-agent", "tucao-cli")

	client := &http.Client{Timeout: 15 * time.Second}
	response, err := client.Do(request)
	if err != nil {
		return nil, NetworkError("查询更新", err)
	}
	defer response.Body.Close()

	if response.StatusCode == http.StatusNotFound {
		return nil, NewError(CodeNotFound, "查询更新", "仓库还没有正式发布")
	}
	if response.StatusCode != http.StatusOK {
		return nil, NewError(CodeUpstream, "查询更新",
			"GitHub 返回状态码 "+itoa(response.StatusCode))
	}
	var payload map[string]any
	if err := json.NewDecoder(response.Body).Decode(&payload); err != nil {
		return nil, WrapError(CodeUpstream, "查询更新", "响应无法解析", err)
	}
	release := ParseRelease(payload)
	if release == nil {
		return nil, NewError(CodeUpstream, "查询更新", "响应里没有版本信息")
	}
	return release, nil
}

// ParseRelease 解析发布内容, 结构不合法时返回 nil.
func ParseRelease(payload map[string]any) *model.Release {
	tag, _ := payload["tag_name"].(string)
	page, _ := payload["html_url"].(string)
	if tag == "" || page == "" {
		return nil
	}
	name, _ := payload["name"].(string)
	if name == "" {
		name = tag
	}
	body, _ := payload["body"].(string)
	published, _ := payload["published_at"].(string)
	prerelease, _ := payload["prerelease"].(bool)
	return &model.Release{
		TagName:     tag,
		Name:        name,
		Body:        body,
		PageURL:     page,
		Prerelease:  prerelease,
		PublishedAt: published,
	}
}
