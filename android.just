[private]
default:
    @just --list --justfile {{justfile_directory()}}/android.just

# 获取 Flutter 依赖.
[group('依赖与环境')]
deps:
    flutter pub get

# 检查可更新的 Flutter 依赖.
[group('依赖与环境')]
outdated:
    flutter pub outdated

# 显示 Flutter 开发环境诊断信息.
[group('依赖与环境')]
doctor:
    flutter doctor -v

# 显示 Flutter 可用设备.
[group('依赖与环境')]
devices:
    flutter devices

# 清理项目构建产物.
[group('依赖与环境')]
clean:
    flutter clean

# 运行 Dart 和 Flutter 静态检查.
[group('检查')]
analyze:
    flutter analyze

# just android test [args...]
# 运行 Flutter 测试.
[group('检查')]
test *args:
    flutter test {{args}}

# just android build [args...]
# 构建 Android Release APK.
[group('构建')]
build *args:
    flutter build apk --release --no-pub {{args}}

# just android build-split [args...]
# 构建分 ABI 的 Android Release APK.
[group('构建')]
build-split *args:
    flutter build apk --release --split-per-abi --no-pub {{args}}

# just android build-debug [args...]
# 构建 Android Debug APK, 用于本地调试.
[group('构建')]
build-debug *args:
    flutter build apk --debug --no-pub {{args}}

# just android bundle [args...]
# 构建用于应用商店发布的 Android App Bundle.
[group('构建')]
bundle *args:
    flutter build appbundle --release --no-pub {{args}}

# 生成发布产物 (按架构拆分的 release apk).
[group('构建')]
dist:
    uv run --no-project python scripts/dist.py

# just android run [args...]
# 在已连接的设备上运行调试构建.
[group('运行')]
run *args:
    flutter run {{args}}

# just android install [args...]
# 安装已构建的 Release APK 到已连接设备.
[group('运行')]
install *args:
    flutter install --release {{args}}

# 查看已连接设备上的应用日志.
[group('运行')]
logs:
    adb logcat -s flutter

# 生成应用图标资源.
[group('生成')]
icons:
    dart run flutter_launcher_icons

# 生成启动画面资源.
[group('生成')]
splash:
    dart run flutter_native_splash:create
