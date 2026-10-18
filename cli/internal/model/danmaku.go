package model

// 弹幕位置, 由站点弹幕类型归一化得到.
const (
	PositionScroll = "scroll"
	PositionTop    = "top"
	PositionBottom = "bottom"
)

// Danmaku 是一条弹幕.
type Danmaku struct {
	// Time 是出现时间, 秒.
	Time float64 `json:"time" yaml:"time"`
	// Mode 是站点弹幕类型: 1 2 3 滚动, 4 底部, 5 顶部, 7 高级弹幕.
	Mode int `json:"mode" yaml:"mode"`
	// Position 是 Mode 归一化后的位置: scroll, top, bottom.
	Position  string `json:"position" yaml:"position"`
	FontSize  int    `json:"font_size" yaml:"font_size"`
	Color     int    `json:"color" yaml:"color"`
	Timestamp int64  `json:"timestamp,omitempty" yaml:"timestamp,omitempty"`
	Text      string `json:"text" yaml:"text"`
}
