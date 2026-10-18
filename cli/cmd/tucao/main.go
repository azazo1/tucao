// Command tucao 是吐槽弹幕网的命令行客户端.
package main

import (
	"context"
	"errors"
	"fmt"
	"os"
	"os/signal"
	"syscall"

	"github.com/azazo1/tucao/cli/internal/cli"
)

func main() {
	app := cli.NewApp()
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	// 第一次 Ctrl-C 取消在途请求, 第二次直接退出.
	interrupts := make(chan os.Signal, 2)
	signal.Notify(interrupts, os.Interrupt, syscall.SIGTERM)
	defer signal.Stop(interrupts)
	go func() {
		<-interrupts
		cancel()
		<-interrupts
		os.Exit(130)
	}()

	err := app.Execute(ctx)
	if err == nil {
		return
	}
	var exitErr *cli.ExitError
	if errors.As(err, &exitErr) {
		os.Exit(exitErr.Code)
	}
	fmt.Fprintln(os.Stderr, err)
	os.Exit(1)
}
