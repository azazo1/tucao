[private]
default:
    @just --list --list-submodules

mod android
mod mock

# 显示项目信息.
info:
    @echo "项目: 吐槽弹幕网客户端"
    @flutter --version

# 观察当前提交的 ci 运行, 等到出结果再退出.
# 认领运行是按本地短 hash 匹配, 因此必须在 push 之后执行.
ci-watch:
    uv run --no-project python scripts/ci_watch.py
