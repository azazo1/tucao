package store

import (
	"fmt"

	"github.com/azazo1/tucao/cli/internal/model"
)

// 本地数据文件的结构版本, 结构变化时递增并补充迁移逻辑.
const (
	FavoritesVersion     = 1
	HistoryVersion       = 1
	SearchHistoryVersion = 1
)

// checkVersion 校验数据文件版本.
//
// 版本号缺失 (旧文件) 按当前结构处理, 高于当前支持版本时直接报错,
// 避免新版字段被旧程序覆盖掉.
func checkVersion(name string, version, current int) error {
	switch {
	case version == 0, version == current:
		return nil
	case version > current:
		return fmt.Errorf("%s 版本 %d 高于当前支持版本 %d", name, version, current)
	default:
		return fmt.Errorf("不支持的 %s 版本: %d", name, version)
	}
}

// FavoriteItem 是本地收藏的一条记录.
type FavoriteItem struct {
	SavedAt int64       `json:"saved_at" yaml:"saved_at"`
	Video   model.Video `json:"video" yaml:"video"`
}

// Favorites 是本地收藏文件的内容.
//
// 与安卓端一致: 按 hid 去重, 新的在最前, 不与站点账号同步.
type Favorites struct {
	Version int            `json:"version" yaml:"version"`
	Items   []FavoriteItem `json:"items" yaml:"items"`
}

// LoadFavorites 读取本地收藏.
func (s *Store) LoadFavorites() (*Favorites, error) {
	favorites := &Favorites{Version: FavoritesVersion, Items: []FavoriteItem{}}
	found, err := s.ReadJSON(FavoritesFile, favorites)
	if err != nil {
		return nil, err
	}
	if favorites.Items == nil {
		favorites.Items = []FavoriteItem{}
	}
	if !found {
		return favorites, nil
	}
	if err := checkVersion("favorites.json", favorites.Version, FavoritesVersion); err != nil {
		return nil, err
	}
	favorites.Version = FavoritesVersion
	return favorites, nil
}

// SaveFavorites 写回本地收藏.
func (s *Store) SaveFavorites(favorites *Favorites) error {
	favorites.Version = FavoritesVersion
	if favorites.Items == nil {
		favorites.Items = []FavoriteItem{}
	}
	return s.WriteJSON(FavoritesFile, favorites)
}

// Contains 判断某个视频是否已在收藏里.
func (f *Favorites) Contains(hid string) bool {
	for _, item := range f.Items {
		if item.Video.HID == hid {
			return true
		}
	}
	return false
}

// Add 新增收藏, 已存在时返回 false.
func (f *Favorites) Add(video model.Video, savedAt int64) bool {
	if f.Contains(video.HID) {
		return false
	}
	f.Items = append([]FavoriteItem{{SavedAt: savedAt, Video: video}}, f.Items...)
	return true
}

// Remove 删除收藏, 不存在时返回 false.
func (f *Favorites) Remove(hid string) bool {
	for index, item := range f.Items {
		if item.Video.HID != hid {
			continue
		}
		f.Items = append(f.Items[:index], f.Items[index+1:]...)
		return true
	}
	return false
}

// HistoryItem 是本地播放历史的一条记录.
type HistoryItem struct {
	Video model.Video `json:"video" yaml:"video"`
	// Part 是从 0 开始的分P序号.
	Part       int     `json:"part" yaml:"part"`
	Progress   float64 `json:"progress" yaml:"progress"`
	Duration   float64 `json:"duration" yaml:"duration"`
	UpdateTime int64   `json:"update_time" yaml:"update_time"`
}

// History 是本地播放历史文件的内容.
type History struct {
	Version int           `json:"version" yaml:"version"`
	Items   []HistoryItem `json:"items" yaml:"items"`
}

// LoadHistory 读取本地播放历史.
func (s *Store) LoadHistory() (*History, error) {
	history := &History{Version: HistoryVersion, Items: []HistoryItem{}}
	found, err := s.ReadJSON(HistoryFile, history)
	if err != nil {
		return nil, err
	}
	if history.Items == nil {
		history.Items = []HistoryItem{}
	}
	if !found {
		return history, nil
	}
	if err := checkVersion("history.json", history.Version, HistoryVersion); err != nil {
		return nil, err
	}
	history.Version = HistoryVersion
	return history, nil
}

// SaveHistory 写回本地播放历史.
func (s *Store) SaveHistory(history *History) error {
	history.Version = HistoryVersion
	if history.Items == nil {
		history.Items = []HistoryItem{}
	}
	return s.WriteJSON(HistoryFile, history)
}

// Record 记录一条进度, 同一视频同一分P只保留最新一条.
func (h *History) Record(item HistoryItem, limit int) {
	next := h.Items[:0]
	for _, existing := range h.Items {
		if existing.Video.HID == item.Video.HID && existing.Part == item.Part {
			continue
		}
		next = append(next, existing)
	}
	h.Items = append([]HistoryItem{item}, next...)
	if limit > 0 && len(h.Items) > limit {
		h.Items = h.Items[:limit]
	}
}

// Remove 删除某个视频的记录, part 为负表示删除该视频的全部分P.
func (h *History) Remove(hid string, part int) int {
	removed := 0
	next := h.Items[:0]
	for _, item := range h.Items {
		if item.Video.HID == hid && (part < 0 || item.Part == part) {
			removed++
			continue
		}
		next = append(next, item)
	}
	h.Items = next
	return removed
}

// Find 查询某个视频某个分P的记录.
func (h *History) Find(hid string, part int) *HistoryItem {
	for index := range h.Items {
		if h.Items[index].Video.HID == hid && h.Items[index].Part == part {
			return &h.Items[index]
		}
	}
	return nil
}

// SearchHistory 是本地搜索历史文件的内容.
type SearchHistory struct {
	Version int      `json:"version" yaml:"version"`
	Items   []string `json:"items" yaml:"items"`
}

// LoadSearchHistory 读取本地搜索历史.
func (s *Store) LoadSearchHistory() (*SearchHistory, error) {
	history := &SearchHistory{Version: SearchHistoryVersion, Items: []string{}}
	found, err := s.ReadJSON(SearchHistoryFile, history)
	if err != nil {
		return nil, err
	}
	if history.Items == nil {
		history.Items = []string{}
	}
	if !found {
		return history, nil
	}
	if err := checkVersion("search_history.json", history.Version, SearchHistoryVersion); err != nil {
		return nil, err
	}
	history.Version = SearchHistoryVersion
	if history.Items == nil {
		history.Items = []string{}
	}
	return history, nil
}

// SaveSearchHistory 写回本地搜索历史.
func (s *Store) SaveSearchHistory(history *SearchHistory) error {
	history.Version = SearchHistoryVersion
	if history.Items == nil {
		history.Items = []string{}
	}
	return s.WriteJSON(SearchHistoryFile, history)
}

// Add 记录关键词, 最新的在最前, 超出上限时截断.
func (h *SearchHistory) Add(keyword string, limit int) {
	next := make([]string, 0, len(h.Items)+1)
	next = append(next, keyword)
	for _, existing := range h.Items {
		if existing == keyword {
			continue
		}
		next = append(next, existing)
	}
	if limit > 0 && len(next) > limit {
		next = next[:limit]
	}
	h.Items = next
}

// Remove 删除一个关键词.
func (h *SearchHistory) Remove(keyword string) bool {
	for index, existing := range h.Items {
		if existing != keyword {
			continue
		}
		h.Items = append(h.Items[:index], h.Items[index+1:]...)
		return true
	}
	return false
}
