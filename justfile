[private]
default:
    @just --list --list-submodules

mod android
mod cli
mod mock

# 显示项目信息.
info:
    @echo "项目: 吐槽弹幕网客户端"
    @flutter --version
