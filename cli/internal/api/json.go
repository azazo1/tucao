package api

import (
	"encoding/json"
	"strconv"
	"strings"
)

// 站点接口的字段类型并不稳定: 同一字段有时是数字, 有时是字符串,
// 有时是空串; 这里用几个宽松类型统一吸收, 解析失败按零值处理,
// 与安卓端 tryParse 的容忍度保持一致.

// FlexString 接受字符串或数字, 统一按字符串使用.
type FlexString string

func (f *FlexString) UnmarshalJSON(data []byte) error {
	text := strings.TrimSpace(string(data))
	if text == "" || text == "null" {
		*f = ""
		return nil
	}
	if strings.HasPrefix(text, "\"") {
		var value string
		if err := json.Unmarshal(data, &value); err != nil {
			return err
		}
		*f = FlexString(value)
		return nil
	}
	*f = FlexString(text)
	return nil
}

func (f FlexString) String() string { return string(f) }

// FlexInt 接受数字或数字字符串, 无法解析时按 0 处理.
type FlexInt int

func (f *FlexInt) UnmarshalJSON(data []byte) error {
	text := strings.Trim(strings.TrimSpace(string(data)), "\"")
	if text == "" || text == "null" {
		*f = 0
		return nil
	}
	value, err := strconv.Atoi(text)
	if err != nil {
		*f = 0
		return nil
	}
	*f = FlexInt(value)
	return nil
}

func (f FlexInt) Int() int { return int(f) }

// FlexFloat 接受数字或数字字符串, 无法解析时按 0 处理.
type FlexFloat float64

func (f *FlexFloat) UnmarshalJSON(data []byte) error {
	text := strings.Trim(strings.TrimSpace(string(data)), "\"")
	if text == "" || text == "null" {
		*f = 0
		return nil
	}
	value, err := strconv.ParseFloat(text, 64)
	if err != nil {
		*f = 0
		return nil
	}
	*f = FlexFloat(value)
	return nil
}

func (f FlexFloat) Float() float64 { return float64(f) }

// envelope 是站点通用响应包装.
type envelope struct {
	Code    FlexString      `json:"code"`
	Message FlexString      `json:"msg"`
	Result  json.RawMessage `json:"result"`
	Total   FlexInt         `json:"total_count"`
}

// succeed 判断接口是否返回成功码.
func (e envelope) succeed() bool {
	return e.Code.String() == "200"
}

// failure 把非 200 的响应转成统一错误.
func (e envelope) failure(action string) error {
	message := e.Message.String()
	if message == "" {
		message = "站点返回 code=" + e.Code.String()
	}
	return NewError(CodeUpstream, action, message)
}

// parseList 解析带 total_count 的列表响应.
func parseList[T any](raw []byte, parse func(json.RawMessage) (T, error)) ([]T, int, error) {
	var payload envelope
	if err := json.Unmarshal(raw, &payload); err != nil {
		return nil, 0, WrapError(CodeUpstream, "解析列表", "接口返回内容无法解析", err)
	}
	if !payload.succeed() {
		return nil, 0, payload.failure("获取列表")
	}
	var items []json.RawMessage
	if len(payload.Result) > 0 && string(payload.Result) != "null" {
		if err := json.Unmarshal(payload.Result, &items); err != nil {
			// 站点偶尔把 result 写成对象而不是数组, 无法解析时按空列表处理.
			return []T{}, payload.Total.Int(), nil
		}
	}
	result := make([]T, 0, len(items))
	for _, item := range items {
		value, err := parse(item)
		if err != nil {
			return nil, 0, err
		}
		result = append(result, value)
	}
	return result, payload.Total.Int(), nil
}

// parseSingle 解析单个对象的响应.
func parseSingle[T any](raw []byte, parse func(json.RawMessage) (T, error)) (T, error) {
	var zero T
	var payload envelope
	if err := json.Unmarshal(raw, &payload); err != nil {
		return zero, WrapError(CodeUpstream, "解析响应", "接口返回内容无法解析", err)
	}
	if !payload.succeed() {
		return zero, payload.failure("获取详情")
	}
	if len(payload.Result) == 0 || string(payload.Result) == "null" {
		return zero, NewError(CodeNotFound, "获取详情", "站点没有返回内容")
	}
	return parse(payload.Result)
}
