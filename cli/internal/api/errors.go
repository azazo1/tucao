package api

import (
	"context"
	"errors"
	"fmt"
	"io"
	"net"
	"net/url"
)

// ErrorCode 是输出 envelope 里的错误码, 同时决定进程退出码.
type ErrorCode string

const (
	CodeNotAuthenticated ErrorCode = "not_authenticated"
	CodePermissionDenied ErrorCode = "permission_denied"
	CodeInvalidInput     ErrorCode = "invalid_input"
	CodeNetwork          ErrorCode = "network_error"
	CodeUpstream         ErrorCode = "upstream_error"
	CodeNotFound         ErrorCode = "not_found"
	CodeInternal         ErrorCode = "internal_error"
)

// Error 是接口层与命令层统一的错误类型.
type Error struct {
	Code    ErrorCode
	Action  string
	Message string
	Status  int
	Err     error
}

func (e *Error) Error() string {
	if e == nil {
		return ""
	}
	switch {
	case e.Action == "":
		return e.Message
	case e.Message == "":
		return e.Action
	default:
		return fmt.Sprintf("%s: %s", e.Action, e.Message)
	}
}

func (e *Error) Unwrap() error { return e.Err }

// NewError 构造一个不带底层错误的错误.
func NewError(code ErrorCode, action, message string) *Error {
	return &Error{Code: code, Action: action, Message: message}
}

// WrapError 构造一个带底层错误的错误.
func WrapError(code ErrorCode, action, message string, err error) *Error {
	return &Error{Code: code, Action: action, Message: message, Err: err}
}

// CodeOf 取出错误的错误码, 未识别时按内部错误处理.
func CodeOf(err error) ErrorCode {
	var apiErr *Error
	if errors.As(err, &apiErr) && apiErr.Code != "" {
		return apiErr.Code
	}
	return CodeInternal
}

// ExitCode 把错误映射成进程退出码.
func ExitCode(err error) int {
	if err == nil {
		return 0
	}
	switch CodeOf(err) {
	case CodeInvalidInput:
		return 2
	case CodeNotAuthenticated:
		return 3
	case CodePermissionDenied:
		return 4
	case CodeNotFound:
		return 5
	default:
		return 1
	}
}

func IsNetwork(err error) bool {
	var apiErr *Error
	return errors.As(err, &apiErr) && apiErr.Code == CodeNetwork
}

func IsAuth(err error) bool {
	var apiErr *Error
	return errors.As(err, &apiErr) && apiErr.Code == CodeNotAuthenticated
}

func IsPermission(err error) bool {
	var apiErr *Error
	return errors.As(err, &apiErr) && apiErr.Code == CodePermissionDenied
}

// NotLoggedIn 是未登录时的统一错误.
func NotLoggedIn(action string) *Error {
	return NewError(CodeNotAuthenticated, action, "请先执行 tucao me login 登录")
}

// PermissionDenied 是 safety 开关拒绝写操作时的统一错误.
func PermissionDenied(action, reason string) *Error {
	return NewError(CodePermissionDenied, action, reason)
}

// NetworkError 把底层网络错误包装成统一错误, 保留原因便于排查.
func NetworkError(action string, err error) *Error {
	if err == nil {
		return NewError(CodeNetwork, action, "网络请求失败")
	}
	if errors.Is(err, context.DeadlineExceeded) || errors.Is(err, context.Canceled) {
		return WrapError(CodeNetwork, action, "请求超时或被取消", err)
	}
	var urlErr *url.Error
	if errors.As(err, &urlErr) {
		return WrapError(CodeNetwork, action, "请求失败: "+urlErr.Error(), err)
	}
	var netErr net.Error
	if errors.As(err, &netErr) {
		return WrapError(CodeNetwork, action, "网络异常: "+netErr.Error(), err)
	}
	if errors.Is(err, io.ErrUnexpectedEOF) || errors.Is(err, io.EOF) {
		return WrapError(CodeNetwork, action, "响应被中断", err)
	}
	return WrapError(CodeNetwork, action, err.Error(), err)
}
