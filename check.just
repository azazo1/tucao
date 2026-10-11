# 获取 Flutter 依赖.
deps:
    flutter pub get

# 检查可更新的 Flutter 依赖.
outdated:
    flutter pub outdated

# 运行 Dart 和 Flutter 静态检查.
analyze:
    flutter analyze

# just check::test [args...]
# 运行 Flutter 测试.
test *args:
    flutter test {{args}}

# 显示 Flutter 开发环境诊断信息.
doctor:
    flutter doctor -v

# 显示 Flutter 可用设备.
devices:
    flutter devices

# 清理项目构建产物.
clean:
    flutter clean
