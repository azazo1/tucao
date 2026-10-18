package model

import (
	"regexp"
	"strconv"
	"strings"
)

// 版本号解析与比较.
//
// 版本号可能来自构建注入 (v1.2.0), 也可能来自 GitHub 标签 (v1.2.0);
// 比较时只取数字段, 前缀 v 与 + / - 之后的内容不参与.

var versionCutPattern = regexp.MustCompile(`[+-]`)
var versionDigitsPattern = regexp.MustCompile(`^\d+`)

// ParseVersion 把版本号拆成数字段, 无法解析的段按 0 处理.
func ParseVersion(raw string) []int {
	text := strings.TrimSpace(raw)
	if strings.HasPrefix(text, "v") || strings.HasPrefix(text, "V") {
		text = text[1:]
	}
	if cut := versionCutPattern.FindStringIndex(text); cut != nil {
		text = text[:cut[0]]
	}
	if text == "" {
		return nil
	}
	parts := strings.Split(text, ".")
	result := make([]int, 0, len(parts))
	for _, part := range parts {
		digits := versionDigitsPattern.FindString(part)
		value, err := strconv.Atoi(digits)
		if err != nil {
			value = 0
		}
		result = append(result, value)
	}
	return result
}

// CompareVersions 比较两个版本号, left 更新时返回正数, 相同返回 0, 更旧返回负数.
func CompareVersions(left, right string) int {
	leftParts := ParseVersion(left)
	rightParts := ParseVersion(right)
	length := len(leftParts)
	if len(rightParts) > length {
		length = len(rightParts)
	}
	for index := 0; index < length; index++ {
		leftValue := 0
		if index < len(leftParts) {
			leftValue = leftParts[index]
		}
		rightValue := 0
		if index < len(rightParts) {
			rightValue = rightParts[index]
		}
		if leftValue != rightValue {
			return leftValue - rightValue
		}
	}
	return 0
}

// IsNewer 判断 candidate 是否比 current 新.
func IsNewer(current, candidate string) bool {
	return CompareVersions(candidate, current) > 0
}
