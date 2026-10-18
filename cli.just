[private]
default:
    @just --list --justfile {{justfile_directory()}}/cli.just

# 构建当前平台的 CLI 二进制到 cli/bin/.
[working-directory('cli')]
build:
    go run ./scripts/release -mode build

# 发布归档的版本号取自 git tag, 与安卓端共用同一套版本号.
# 生成当前平台的发布归档到 cli/dist/.
[working-directory('cli')]
dist:
    go run ./scripts/release -mode dist

# 交叉编译全部六个平台到 cli/bin/ 与 cli/dist/, 并校验产物.
# 纯 Go 代码不依赖 cgo, 一个平台就能产出全部目标.
[working-directory('cli')]
dist-all:
    go run ./scripts/release -mode dist-all
    go run ./scripts/release -mode verify

# just cli test [args...]
# 运行 Go 测试.
[working-directory('cli')]
test *args:
    go test ./... {{args}}

# 运行 go vet 静态检查.
[working-directory('cli')]
lint:
    go vet ./...

# 用 gofmt 就地格式化源码.
[working-directory('cli')]
fmt:
    gofmt -w ./cmd ./internal ./scripts

# just cli run --json rank --type hot
# 直接运行 CLI, 不安装到 PATH.
[working-directory('cli')]
run *args:
    go run ./cmd/tucao {{args}}
