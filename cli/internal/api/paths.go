package api

import (
	"net/url"
	"strconv"
	"strings"
)

// 站点接口路径, 沿用官方安卓端的划分.
const (
	// PathList 是分区列表接口.
	PathList = "list.php"
	// PathSearch 是搜索接口.
	PathSearch = "search.php"
	// PathView 是视频详情接口.
	PathView = "view.php"
	// PathIndex 是 discuz 模块化入口.
	PathIndex = "index.php"
	// PathAPI 是站点杂项接口入口.
	PathAPI = "api.php"
	// PathOnline 是在线人数脚本.
	PathOnline = "ol.php"

	// 站点页面路径.
	PathHome          = ""
	PathRankHot       = "html/hot.html"
	PathRankDanmaku   = "html/danmu.html"
	PathRankDigg      = "html/digg.html"
	PathRankZero      = "html/zero.html"
	PathRankFav       = "html/fav_hot.html"
	PathRankOnline    = "html/ol.html"
	PathRankNew       = "html/new.html"
	PathRankRecommend = "html/pos.html"
	PathHotSearch     = "html/hot_search.html"
	PathUserRank      = "html/user_hot.html"
	PathWeekBgm       = "html/week_bgm.html"
	PathBgmIndex      = "bgm/"
	PathArticleList   = "data/"
)

// IndexPath 构造 index.php 的模块化地址.
//
// 站点用 m/c/a 三个查询参数区分模块, 这里把它们与附加参数合并.
func IndexPath(module, controller, action string, extra url.Values) (string, url.Values) {
	query := url.Values{}
	if module != "" {
		query.Set("m", module)
	}
	if controller != "" {
		query.Set("c", controller)
	}
	if action != "" {
		query.Set("a", action)
	}
	for key, values := range extra {
		for _, value := range values {
			query.Add(key, value)
		}
	}
	return PathIndex, query
}

// APIPath 构造 api.php 的地址, op 是接口名.
func APIPath(op string, extra url.Values) (string, url.Values) {
	query := url.Values{}
	if op != "" {
		query.Set("op", op)
	}
	for key, values := range extra {
		for _, value := range values {
			query.Add(key, value)
		}
	}
	return PathAPI, query
}

// PlayerID 生成弹幕接口需要的播放器 id.
//
// 与官方一致: `{分区}-{hid}-1-{分P序号}`, 分P序号从 0 开始,
// 它是弹幕按分P区分的依据.
func PlayerID(typeID int, hid string, part int) string {
	return strconv.Itoa(typeID) + "-" + hid + "-1-" + strconv.Itoa(part)
}

// CommentID 生成评论接口需要的楼层 id.
//
// 末尾的 1 是固定值, 不是分P序号, 同一视频的所有分P共用一个楼层.
func CommentID(typeID int, hid string) string {
	return "content_" + strconv.Itoa(typeID) + "-" + hid + "-1"
}

// PlayPath 是视频播放页的相对路径.
func PlayPath(hid string) string {
	return "play/h" + hid + "/"
}

// ArticlePlayPath 是档案详情页的相对路径.
func ArticlePlayPath(hid string) string {
	return "play/d" + hid + "/"
}

// UserPath 是用户空间的相对路径.
func UserPath(userID int) string {
	return "play/u" + strconv.Itoa(userID) + "/"
}

// PlayURL 是视频播放页的完整地址.
func PlayURL(baseURL, hid string) string {
	return strings.TrimSuffix(baseURL, "/") + "/" + PlayPath(hid)
}

// ArticlePlayURL 是档案详情页的完整地址.
func ArticlePlayURL(baseURL, hid string) string {
	return strings.TrimSuffix(baseURL, "/") + "/" + ArticlePlayPath(hid)
}

// UserURL 是用户空间的完整地址.
func UserURL(baseURL string, userID int) string {
	return strings.TrimSuffix(baseURL, "/") + "/" + UserPath(userID)
}

// OnlineCID 是内容在在线人数接口里的编号, 由 hid 拼接内容模型 id 得到.
func OnlineCID(hid string, modelID int) string {
	return hid + strconv.Itoa(modelID)
}
