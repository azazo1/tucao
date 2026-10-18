package store

import (
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"

	"github.com/azazo1/tucao/cli/internal/model"
)

func newTestStore(t *testing.T) *Store {
	t.Helper()
	return &Store{Dir: t.TempDir()}
}

func sampleVideo(hid string) model.Video {
	return model.Video{HID: hid, Title: "视频 " + hid, TypeID: 11, TypeName: "连载新番"}
}

func TestFavoritesLifecycle(t *testing.T) {
	store := newTestStore(t)
	favorites, err := store.LoadFavorites()
	if err != nil {
		t.Fatalf("读取空收藏失败: %v", err)
	}
	if favorites.Items == nil || len(favorites.Items) != 0 {
		t.Fatalf("空收藏应是空数组: %+v", favorites.Items)
	}

	if !favorites.Add(sampleVideo("1001"), 100) {
		t.Fatal("首次加入应成功")
	}
	if favorites.Add(sampleVideo("1001"), 200) {
		t.Fatal("重复加入应被忽略")
	}
	favorites.Add(sampleVideo("1002"), 300)
	if len(favorites.Items) != 2 {
		t.Fatalf("收藏条数错误: %d", len(favorites.Items))
	}
	if favorites.Items[0].Video.HID != "1002" {
		t.Fatalf("最新收藏应在最前: %+v", favorites.Items[0])
	}
	if err := store.SaveFavorites(favorites); err != nil {
		t.Fatalf("保存收藏失败: %v", err)
	}

	reloaded, err := store.LoadFavorites()
	if err != nil {
		t.Fatalf("重新读取收藏失败: %v", err)
	}
	if !reloaded.Contains("1001") || len(reloaded.Items) != 2 {
		t.Fatalf("收藏没有正确持久化: %+v", reloaded.Items)
	}
	info, err := os.Stat(store.Path(FavoritesFile))
	if err != nil {
		t.Fatalf("读取文件信息失败: %v", err)
	}
	// Windows 不支持 unix 权限位, 读取到的永远是 0666 或 0444.
	if runtime.GOOS != "windows" && info.Mode().Perm() != 0o600 {
		t.Fatalf("数据文件权限应为 0600, 实际 %v", info.Mode().Perm())
	}
	if !reloaded.Remove("1001") {
		t.Fatal("删除已存在的收藏应成功")
	}
	if reloaded.Remove("1001") {
		t.Fatal("删除不存在的收藏应返回 false")
	}
}

func TestFavoritesRejectsFutureVersion(t *testing.T) {
	store := newTestStore(t)
	if err := os.WriteFile(store.Path(FavoritesFile), []byte(`{"version":99,"items":[]}`), 0o600); err != nil {
		t.Fatalf("写入文件失败: %v", err)
	}
	if _, err := store.LoadFavorites(); err == nil {
		t.Fatal("高于当前版本的数据应当报错")
	} else if !strings.Contains(err.Error(), "版本") {
		t.Fatalf("错误信息应说明版本问题: %v", err)
	}
}

func TestHistoryRecordAndLimit(t *testing.T) {
	store := newTestStore(t)
	history, err := store.LoadHistory()
	if err != nil {
		t.Fatalf("读取空历史失败: %v", err)
	}
	history.Record(HistoryItem{Video: sampleVideo("1001"), Part: 0, Progress: 10, Duration: 100, UpdateTime: 1}, 3)
	history.Record(HistoryItem{Video: sampleVideo("1002"), Part: 0, Progress: 20, Duration: 100, UpdateTime: 2}, 3)
	// 同一视频同一分P只保留最新一条.
	history.Record(HistoryItem{Video: sampleVideo("1001"), Part: 0, Progress: 30, Duration: 100, UpdateTime: 3}, 3)
	if len(history.Items) != 2 {
		t.Fatalf("同一分P不应重复记录: %+v", history.Items)
	}
	if history.Items[0].Progress != 30 {
		t.Fatalf("最新进度应在最前: %+v", history.Items[0])
	}
	history.Record(HistoryItem{Video: sampleVideo("1003"), Part: 0, UpdateTime: 4}, 2)
	history.Record(HistoryItem{Video: sampleVideo("1004"), Part: 0, UpdateTime: 5}, 2)
	if len(history.Items) != 2 {
		t.Fatalf("超出上限时应截断: %d", len(history.Items))
	}
	if found := history.Find("1004", 0); found == nil {
		t.Fatal("应能按 hid 与分P查到记录")
	}
	if removed := history.Remove("1004", -1); removed != 1 {
		t.Fatalf("删除数量错误: %d", removed)
	}
	if history.Find("1004", 0) != nil {
		t.Fatal("删除后不应再查到")
	}
	if err := store.SaveHistory(history); err != nil {
		t.Fatalf("保存历史失败: %v", err)
	}
	reloaded, err := store.LoadHistory()
	if err != nil {
		t.Fatalf("重新读取历史失败: %v", err)
	}
	if len(reloaded.Items) != len(history.Items) {
		t.Fatalf("历史没有正确持久化: %d", len(reloaded.Items))
	}
}

func TestSearchHistory(t *testing.T) {
	store := newTestStore(t)
	history, err := store.LoadSearchHistory()
	if err != nil {
		t.Fatalf("读取搜索历史失败: %v", err)
	}
	if history.Items == nil {
		t.Fatal("空搜索历史应是空数组")
	}
	history.Add("火影", 3)
	history.Add("柯南", 3)
	history.Add("火影", 3)
	if len(history.Items) != 2 || history.Items[0] != "火影" {
		t.Fatalf("搜索历史去重或排序不正确: %+v", history.Items)
	}
	history.Add("one", 3)
	history.Add("two", 3)
	if len(history.Items) != 3 {
		t.Fatalf("搜索历史应受上限约束: %+v", history.Items)
	}
	if !history.Remove("one") {
		t.Fatal("删除存在的关键词应成功")
	}
	if history.Remove("one") {
		t.Fatal("删除不存在的关键词应返回 false")
	}
	if err := store.SaveSearchHistory(history); err != nil {
		t.Fatalf("保存搜索历史失败: %v", err)
	}
	reloaded, err := store.LoadSearchHistory()
	if err != nil {
		t.Fatalf("重新读取搜索历史失败: %v", err)
	}
	if len(reloaded.Items) != len(history.Items) {
		t.Fatalf("搜索历史没有正确持久化: %+v", reloaded.Items)
	}
}

func TestReadJSONKeepsOriginalOnBrokenFile(t *testing.T) {
	store := newTestStore(t)
	path := store.Path(FavoritesFile)
	if err := os.WriteFile(path, []byte("{ 不是 json"), 0o600); err != nil {
		t.Fatalf("写入文件失败: %v", err)
	}
	if _, err := store.LoadFavorites(); err == nil {
		t.Fatal("损坏的文件应当报错")
	}
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("读取文件失败: %v", err)
	}
	if string(data) != "{ 不是 json" {
		t.Fatalf("读取失败不应改写原文件: %s", data)
	}
}

func TestRemoveIgnoresMissingFile(t *testing.T) {
	store := newTestStore(t)
	if err := store.Remove(HistoryFile); err != nil {
		t.Fatalf("删除不存在的文件不应报错: %v", err)
	}
	if _, err := os.Stat(filepath.Join(store.Dir, HistoryFile)); !os.IsNotExist(err) {
		t.Fatalf("文件不应存在: %v", err)
	}
}
