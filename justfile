[private]
default:
    @just --list --list-submodules

mod build
mod check
mod device
mod generate

# 显示项目信息.
info:
    @echo "项目: 吐槽弹幕网客户端"
    @flutter --version

# 生成发布产物 (按架构拆分的 release apk).
dist:
    uv run --no-project python scripts/dist.py
