package cli

import (
	"github.com/azazo1/tucao/cli/internal/api"
)

// requireWrite 检查写操作是否被 safety 开关允许.
//
// safety.read_only 会拒绝全部账号侧写操作, 只读查询与下载仍然可用,
// 登录与登出不受影响, 否则用户无法自己解开限制.
func (a *App) requireWrite(action string) error {
	if a.Config.Safety.ReadOnly {
		return api.PermissionDenied(action, "配置里开启了 safety.read_only, 已拒绝写操作")
	}
	return nil
}

// requireLoginWrite 组合检查写开关与登录态.
func (a *App) requireLoginWrite(action string) error {
	if err := a.requireWrite(action); err != nil {
		return err
	}
	return a.requireLogin(action)
}

// requireDestructive 检查删除与清空类操作.
//
// safety.non_destructive 会全部拒绝; safety.confirm_dangerous_actions
// 要求调用方显式带 --yes, 非交互场景不做兜底确认, 避免脚本误删.
func (a *App) requireDestructive(action string, confirmed bool) error {
	if a.Config.Safety.NonDestructive {
		return api.PermissionDenied(action, "配置里开启了 safety.non_destructive, 已拒绝删除与清空操作")
	}
	if a.Config.Safety.ConfirmDangerousActions && !confirmed {
		return api.PermissionDenied(action, "该操作会改动本地数据, 需要加 --yes 确认")
	}
	return nil
}
