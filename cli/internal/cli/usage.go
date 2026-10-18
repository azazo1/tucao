package cli

import (
	"fmt"
	"strings"

	"github.com/spf13/cobra"

	"github.com/azazo1/tucao/cli/internal/api"
	"github.com/azazo1/tucao/cli/internal/output"
)

// configureUsageErrors 让参数错误也走统一的错误输出与退出码.
func configureUsageErrors(root *cobra.Command, app *App) {
	root.SetFlagErrorFunc(func(command *cobra.Command, err error) error {
		return app.failUsage(command, err)
	})
	configureArgumentErrors(root, app)
}

func configureArgumentErrors(command *cobra.Command, app *App) {
	if validate := command.Args; validate != nil {
		command.Args = func(cmd *cobra.Command, args []string) error {
			if err := validate(cmd, args); err != nil {
				return app.failUsage(cmd, err)
			}
			return nil
		}
	}
	for _, child := range command.Commands() {
		configureArgumentErrors(child, app)
	}
}

// failUsage 报告用法错误, 结构化输出里附带命令用法.
func (a *App) failUsage(command *cobra.Command, err error) error {
	apiErr := api.NewError(api.CodeInvalidInput, "", err.Error())
	mode := a.usageMode(command)
	usage := strings.TrimSpace(command.UsageString())
	if mode == output.ModeRich {
		if emitErr := a.Out.EmitError(string(apiErr.Code), apiErr.Message, nil, mode); emitErr != nil {
			fmt.Fprintln(a.Out.Stderr, apiErr.Message)
		}
		if usage != "" {
			fmt.Fprintln(a.Out.Stderr)
			fmt.Fprintln(a.Out.Stderr, usage)
		}
		return &ExitError{Code: api.ExitCode(apiErr)}
	}
	details := map[string]any{"usage": usage}
	if emitErr := a.Out.EmitError(string(apiErr.Code), apiErr.Message, details, mode); emitErr != nil {
		fmt.Fprintln(a.Out.Stderr, apiErr.Message)
	}
	return &ExitError{Code: api.ExitCode(apiErr)}
}

// usageMode 解析用法错误的输出格式, 参数还没解析完时退回 rich.
func (a *App) usageMode(command *cobra.Command) output.Mode {
	if command == nil {
		return output.ModeRich
	}
	asJSON, _ := command.Flags().GetBool("json")
	asYAML, _ := command.Flags().GetBool("yaml")
	if !asJSON && !asYAML && a.Out.UsesAutoMode() {
		return output.ModeRich
	}
	mode, err := a.Out.Resolve(asJSON, asYAML)
	if err != nil {
		return output.ModeRich
	}
	return mode
}
