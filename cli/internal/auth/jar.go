package auth

import (
	"net/http"
	"net/url"
	"sort"
	"strings"
	"sync"
	"time"
)

// Cookie 是 auth.json 里保存的一条 cookie.
type Cookie struct {
	Name     string `json:"name"`
	Value    string `json:"value"`
	Domain   string `json:"domain"`
	Path     string `json:"path"`
	Expires  int64  `json:"expires,omitempty"`
	Secure   bool   `json:"secure,omitempty"`
	HTTPOnly bool   `json:"http_only,omitempty"`
	// HostOnly 表示这条 cookie 没有 Domain 属性, 只对设置它的主机生效.
	HostOnly bool `json:"host_only,omitempty"`
}

// Jar 是站点 cookie 的容器, 实现 http.CookieJar.
//
// 自己存一份而不是用 net/http/cookiejar, 是为了把会话 cookie 按站点
// 登录态长期保留 (安卓端的 PersistCookieJar 也是 ignoreExpires),
// 同时保证每次变更都能立刻回写 auth.json.
type Jar struct {
	mu       sync.Mutex
	entries  map[string]Cookie
	onChange func()
}

// newJar 构造 cookie 容器, onChange 在 cookie 变化后调用.
func newJar(onChange func()) *Jar {
	return &Jar{entries: map[string]Cookie{}, onChange: onChange}
}

func keyOf(domain, path, name string) string {
	return domain + "\t" + path + "\t" + name
}

// SetCookies 写入响应返回的 cookie.
func (j *Jar) SetCookies(target *url.URL, cookies []*http.Cookie) {
	if target == nil || len(cookies) == 0 {
		return
	}
	j.mu.Lock()
	changed := false
	for _, cookie := range cookies {
		if cookie == nil || cookie.Name == "" {
			continue
		}
		record := Cookie{
			Name:     cookie.Name,
			Value:    cookie.Value,
			Domain:   strings.ToLower(strings.TrimPrefix(cookie.Domain, ".")),
			Path:     cookie.Path,
			Secure:   cookie.Secure,
			HTTPOnly: cookie.HttpOnly,
			HostOnly: cookie.Domain == "",
		}
		if record.Path == "" {
			record.Path = "/"
		}
		if record.HostOnly {
			record.Domain = strings.ToLower(target.Hostname())
		}
		if !cookie.Expires.IsZero() {
			record.Expires = cookie.Expires.Unix()
		}
		key := keyOf(record.Domain, record.Path, record.Name)
		if cookie.MaxAge < 0 {
			if _, exists := j.entries[key]; exists {
				delete(j.entries, key)
				changed = true
			}
			continue
		}
		if existing, exists := j.entries[key]; !exists || existing.Value != record.Value {
			j.entries[key] = record
			changed = true
		}
	}
	j.mu.Unlock()
	if changed && j.onChange != nil {
		j.onChange()
	}
}

// Cookies 返回适用于目标地址的 cookie.
func (j *Jar) Cookies(target *url.URL) []*http.Cookie {
	if target == nil {
		return nil
	}
	host := strings.ToLower(target.Hostname())
	path := target.Path
	if path == "" {
		path = "/"
	}
	secure := target.Scheme == "https"

	j.mu.Lock()
	defer j.mu.Unlock()
	result := make([]*http.Cookie, 0, len(j.entries))
	for _, record := range j.entries {
		if !domainMatches(host, record) {
			continue
		}
		if !strings.HasPrefix(path, record.Path) {
			continue
		}
		if record.Secure && !secure {
			continue
		}
		result = append(result, &http.Cookie{
			Name:     record.Name,
			Value:    record.Value,
			Path:     record.Path,
			Domain:   record.Domain,
			Secure:   record.Secure,
			HttpOnly: record.HTTPOnly,
		})
	}
	sort.Slice(result, func(left, right int) bool { return result[left].Name < result[right].Name })
	return result
}

// Entries 返回全部 cookie, 顺序稳定, 便于回写文件.
func (j *Jar) Entries() []Cookie {
	j.mu.Lock()
	defer j.mu.Unlock()
	result := make([]Cookie, 0, len(j.entries))
	for _, record := range j.entries {
		result = append(result, record)
	}
	sort.Slice(result, func(left, right int) bool {
		if result[left].Domain != result[right].Domain {
			return result[left].Domain < result[right].Domain
		}
		if result[left].Path != result[right].Path {
			return result[left].Path < result[right].Path
		}
		return result[left].Name < result[right].Name
	})
	return result
}

// Load 用文件里的记录替换当前内容, 不触发回写.
func (j *Jar) Load(records []Cookie) {
	j.mu.Lock()
	defer j.mu.Unlock()
	j.entries = make(map[string]Cookie, len(records))
	for _, record := range records {
		if record.Name == "" {
			continue
		}
		if record.Path == "" {
			record.Path = "/"
		}
		j.entries[keyOf(record.Domain, record.Path, record.Name)] = record
	}
}

// Clear 清空全部 cookie.
func (j *Jar) Clear() {
	j.mu.Lock()
	j.entries = map[string]Cookie{}
	j.mu.Unlock()
}

// Set 手动写入一条 cookie, 用于从环境变量导入.
func (j *Jar) Set(host, name, value string) {
	j.mu.Lock()
	j.entries[keyOf(strings.ToLower(host), "/", name)] = Cookie{
		Name:     name,
		Value:    value,
		Domain:   strings.ToLower(host),
		Path:     "/",
		HostOnly: true,
	}
	j.mu.Unlock()
	if j.onChange != nil {
		j.onChange()
	}
}

// Count 返回 cookie 条数.
func (j *Jar) Count() int {
	j.mu.Lock()
	defer j.mu.Unlock()
	return len(j.entries)
}

// IsExpired 判断记录是否已经过期, 会话 cookie 视为长期有效.
func (record Cookie) IsExpired(now time.Time) bool {
	if record.Expires <= 0 {
		return false
	}
	return now.Unix() > record.Expires
}

func domainMatches(host string, record Cookie) bool {
	domain := strings.ToLower(record.Domain)
	if domain == "" {
		return false
	}
	if record.HostOnly {
		return host == domain
	}
	return host == domain || strings.HasSuffix(host, "."+domain)
}
