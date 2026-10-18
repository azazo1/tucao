package auth

import (
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"runtime"
	"testing"
	"time"

	"github.com/azazo1/tucao/cli/internal/model"
)

// user 是测试用的登录用户.
var user = model.User{UserID: 42, UserName: "tester"}

func testStore(t *testing.T) *Store {
	t.Helper()
	dir := t.TempDir()
	store := &Store{Dir: dir, File: filepath.Join(dir, "auth.json")}
	store.jar = newJar(func() { store.persistAfterChange() })
	return store
}

func mustURL(t *testing.T, raw string) *url.URL {
	t.Helper()
	parsed, err := url.Parse(raw)
	if err != nil {
		t.Fatalf("解析地址失败: %v", err)
	}
	return parsed
}

func TestJarMatching(t *testing.T) {
	jar := newJar(nil)
	jar.SetCookies(mustURL(t, "https://www.tucao.my/"), []*http.Cookie{
		{Name: "session", Value: "abc", Path: "/"},
		{Name: "scoped", Value: "xyz", Path: "/play/"},
		{Name: "other", Value: "1", Domain: "example.com", Path: "/"},
	})
	onSite := jar.Cookies(mustURL(t, "https://www.tucao.my/api_v2/list.php"))
	if len(onSite) != 1 || onSite[0].Name != "session" {
		t.Fatalf("站点根路径应只带 session: %+v", onSite)
	}
	onPlay := jar.Cookies(mustURL(t, "https://www.tucao.my/play/h1/"))
	if len(onPlay) != 2 {
		t.Fatalf("播放页应带两条 cookie: %+v", onPlay)
	}
	if got := jar.Cookies(mustURL(t, "https://other.example/")); len(got) != 0 {
		t.Fatalf("别的域名不应拿到 cookie: %+v", got)
	}
}

func TestJarKeepsSessionCookie(t *testing.T) {
	jar := newJar(nil)
	jar.SetCookies(mustURL(t, "https://www.tucao.my/"), []*http.Cookie{
		{Name: "verify", Value: "ok", Path: "/"},
	})
	// 会话 cookie 没有过期时间, 重启后仍然要能拿到, 与安卓端的 ignoreExpires 一致.
	if got := jar.Cookies(mustURL(t, "https://www.tucao.my/")); len(got) != 1 {
		t.Fatalf("会话 cookie 应保留: %+v", got)
	}
	entries := jar.Entries()
	if len(entries) != 1 || entries[0].Expires != 0 || !entries[0].HostOnly {
		t.Fatalf("会话 cookie 的记录不正确: %+v", entries[0])
	}
}

func TestJarDeletesCookieWithMaxAge(t *testing.T) {
	jar := newJar(nil)
	target := mustURL(t, "https://www.tucao.my/")
	jar.SetCookies(target, []*http.Cookie{{Name: "gone", Value: "1", Path: "/"}})
	jar.SetCookies(target, []*http.Cookie{{Name: "gone", Value: "", Path: "/", MaxAge: -1}})
	if got := jar.Cookies(target); len(got) != 0 {
		t.Fatalf("MaxAge 为负时应删除 cookie: %+v", got)
	}
}

func TestStoreRoundTrip(t *testing.T) {
	store := testStore(t)
	store.SetUser(nil)
	if err := store.Save(); err != nil {
		t.Fatalf("保存空登录态失败: %v", err)
	}
	if _, err := os.Stat(store.File); !os.IsNotExist(err) {
		t.Fatalf("没有内容时不应写入文件: %v", err)
	}

	store.jar.SetCookies(mustURL(t, "https://www.tucao.my/"), []*http.Cookie{
		{Name: "auth", Value: "token", Path: "/"},
	})
	store.SetUser(&user)
	if _, err := os.Stat(store.File); err != nil {
		t.Fatalf("cookie 变化后应写入文件: %v", err)
	}
	info, err := os.Stat(store.File)
	if err != nil {
		t.Fatalf("读取文件信息失败: %v", err)
	}
	// Windows 不支持 unix 权限位, 读取到的永远是 0666 或 0444.
	if runtime.GOOS != "windows" && info.Mode().Perm() != 0o600 {
		t.Fatalf("auth.json 权限应为 0600, 实际 %v", info.Mode().Perm())
	}

	reloaded := testStore(t)
	reloaded.Dir, reloaded.File = store.Dir, store.File
	if err := reloaded.Load(); err != nil {
		t.Fatalf("读取登录态失败: %v", err)
	}
	if !reloaded.LoggedIn() || reloaded.User().UserName != "tester" {
		t.Fatalf("登录用户没有正确恢复: %+v", reloaded.User())
	}
	if reloaded.CookieCount() != 1 {
		t.Fatalf("cookie 没有正确恢复: %d", reloaded.CookieCount())
	}
	if err := reloaded.Clear(); err != nil {
		t.Fatalf("清除登录态失败: %v", err)
	}
	if reloaded.CookieCount() != 0 || reloaded.LoggedIn() {
		t.Fatal("清除后不应还有登录态")
	}
	if _, err := os.Stat(store.File); !os.IsNotExist(err) {
		t.Fatalf("清除后文件应被删除: %v", err)
	}
}

func TestStoreRejectsFutureVersion(t *testing.T) {
	store := testStore(t)
	if err := os.WriteFile(store.File, []byte(`{"version":99,"cookies":[]}`), 0o600); err != nil {
		t.Fatalf("写入文件失败: %v", err)
	}
	if err := store.Load(); err == nil {
		t.Fatal("高于当前版本的文件应当报错")
	}
}

func TestImportCookieHeader(t *testing.T) {
	store := testStore(t)
	count := store.ImportCookieHeader("www.tucao.my", "a=1; b=2; broken")
	if count != 2 {
		t.Fatalf("应导入 2 条 cookie, 实际 %d", count)
	}
	cookies := store.jar.Cookies(mustURL(t, "https://www.tucao.my/"))
	if len(cookies) != 2 {
		t.Fatalf("导入的 cookie 不可用: %+v", cookies)
	}
}

func TestIsExpired(t *testing.T) {
	now := time.Now()
	if (Cookie{Expires: 0}).IsExpired(now) {
		t.Fatal("没有过期时间的 cookie 不应判为过期")
	}
	if (Cookie{Expires: now.Add(-time.Hour).Unix()}).IsExpired(now) == false {
		t.Fatal("已过期的 cookie 应判为过期")
	}
}
