package output

import (
	"fmt"
	"io"
	"strings"

	"github.com/mattn/go-runewidth"
)

// TableOptions 控制表格排版.
type TableOptions struct {
	// Interactive 表示目标是交互终端, 为假时输出 TSV.
	Interactive bool
	// Width 是终端宽度, 交互模式下用于截断.
	Width int
	// NoTruncate 为真时不做按宽度截断.
	NoTruncate bool
}

// 表格列的最小宽度, 再窄就没有可读性了.
const minColumnWidth = 4

// RenderTable 输出表格.
//
// 交互终端按内容对齐并可按终端宽度截断, 其它情况输出未截断的 TSV,
// 方便脚本与 agent 直接按制表符切分.
func RenderTable(destination io.Writer, title string, headers []string, rows [][]string, options TableOptions) {
	if destination == nil {
		return
	}
	if len(headers) == 0 {
		return
	}
	if !options.Interactive {
		writeTSV(destination, headers, rows)
		return
	}

	widths := columnWidths(headers, rows)
	if !options.NoTruncate && options.Width > 0 {
		shrink(widths, options.Width)
	}
	if title != "" {
		fmt.Fprintln(destination, title)
	}
	writeRow(destination, headers, widths)
	separators := make([]string, len(widths))
	for index, width := range widths {
		separators[index] = strings.Repeat("-", width)
	}
	writeRow(destination, separators, widths)
	for _, row := range rows {
		writeRow(destination, row, widths)
	}
}

func writeTSV(destination io.Writer, headers []string, rows [][]string) {
	clean := func(cell string) string {
		return strings.NewReplacer("\t", " ", "\n", " ", "\r", " ").Replace(cell)
	}
	format := func(cells []string) {
		parts := make([]string, len(cells))
		for index, cell := range cells {
			if index < len(headers) {
				parts[index] = clean(cell)
			}
		}
		fmt.Fprintln(destination, strings.Join(parts, "\t"))
	}
	format(headers)
	for _, row := range rows {
		format(row)
	}
}

func columnWidths(headers []string, rows [][]string) []int {
	widths := make([]int, len(headers))
	for index, header := range headers {
		widths[index] = runewidth.StringWidth(header)
	}
	for _, row := range rows {
		for index := range headers {
			if index >= len(row) {
				continue
			}
			if width := runewidth.StringWidth(row[index]); width > widths[index] {
				widths[index] = width
			}
		}
	}
	return widths
}

// shrink 把总宽度压到终端宽度以内, 从最宽的一列开始逐列收窄.
func shrink(widths []int, limit int) {
	const gap = 2
	total := func() int {
		sum := gap * (len(widths) - 1)
		for _, width := range widths {
			sum += width
		}
		return sum
	}
	for total() > limit {
		widest := 0
		for index, width := range widths {
			if width > widths[widest] {
				widest = index
			}
		}
		if widths[widest] <= minColumnWidth {
			return
		}
		widths[widest]--
	}
}

func writeRow(destination io.Writer, cells []string, widths []int) {
	parts := make([]string, len(widths))
	for index, width := range widths {
		cell := ""
		if index < len(cells) {
			cell = cells[index]
		}
		parts[index] = pad(runewidth.Truncate(cell, width, "..."), width)
	}
	fmt.Fprintln(destination, strings.TrimRight(strings.Join(parts, "  "), " "))
}

// pad 用空格补齐到显示宽度.
func pad(text string, width int) string {
	padding := width - runewidth.StringWidth(text)
	if padding <= 0 {
		return text
	}
	return text + strings.Repeat(" ", padding)
}
