package cli

import (
	"context"
	"errors"
	"io"
	"log/slog"
)

// runForTest 用给定参数执行一次命令, 与 Execute 的退出码映射保持一致.
//
// 单独抽出来是为了让测试能重复执行不同参数, 而不必重建整个进程.
func (a *App) runForTest(ctx context.Context, args ...string) error {
	a.root = a.newRoot()
	a.root.SetArgs(args)
	// 让 cobra 的帮助与提示也写进测试缓冲区.
	a.root.SetOut(a.Out.Stdout)
	a.root.SetErr(a.Out.Stderr)
	if err := a.root.ExecuteContext(ctx); err != nil {
		var exitErr *ExitError
		if errors.As(err, &exitErr) {
			return err
		}
		if looksLikeUsageError(err) {
			return a.failUsage(a.root, err)
		}
		return a.fail(a.root, err, "")
	}
	return nil
}

// discardLogger 返回丢弃输出的日志, 避免测试里打印噪声.
func discardLogger() *slog.Logger {
	return slog.New(slog.NewTextHandler(io.Discard, &slog.HandlerOptions{Level: slog.LevelError}))
}
